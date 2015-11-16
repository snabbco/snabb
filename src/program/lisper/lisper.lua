module(..., package.seeall)

local ffi      = require("ffi")
local lib      = require("core.lib")
local packet   = require("core.packet")
local usage    = require("program.lisper.README_inc")
local ipv6     = require("lib.protocol.ipv6")
local ethernet = require("lib.protocol.ethernet")
local unix     = require("apps.socket.unix")
local raw      = require("apps.socket.raw")
local lines    = require("apps.lines")
local nd       = require("apps.ipv6.nd_light")

local function assert(v, ...)
   if v then return v, ... end
   error(tostring((...)), 2)
end

--program args ---------------------------------------------------------------

local DEBUG        = os.getenv"DEBUG"
local CONTROL_SOCK = "/var/tmp/ctrl.socket"
local PUNT_IF      = "veth0"
local NET_IF       = "e0"
local LOCAL_IP     = ipv6:pton"fd80:4::2"
local LOCAL_MAC    = ethernet:pton"00:00:00:00:01:04"
local NEXT_HOP_IP  = ipv6:pton"fd80:4::1"

local long_opts = {
   control = "c",
   ["punt-interface"] = "p",
   ["network-device"] = "n",
   ["local-ip"] = "i",
   ["local-mac"] = "m",
   ["next-hop"] = "N",
   help = "h",
}
local opt = {}
function opt.h (arg) print(usage) main.exit(0) end
function opt.c (arg) CONTROL_SOCK = arg end
function opt.p (arg) PUNT_IF = arg end
function opt.n (arg) NET_IF = arg end
function opt.i (arg) LOCAL_IP = assert(ipv6:pton(arg)) end
function opt.m (arg) LOCAL_MAC = assert(ethernet:pton(arg)) end
function opt.N (arg) NEXT_HOP_IP = assert(ipv6:pton(arg)) end

local function parse_args(args)
   return lib.dogetopt(args, opt, "hc:p:n:i:m:N:", long_opts)
end

--control plane --------------------------------------------------------------

local function parse_fib_line(s)
   local id, mac, ips = s:match"^%s*%[([^%]]+)%]%s*([^%s]+)%s+(.*)$"
   local id = assert(tonumber(id), "invalid FIB line: "..s)
   local mac = ffi.string(ethernet:pton(mac), 6)
   local t = {}
   for ip in ips:split"%s*,%s*" do
      t[#t+1] = assert(ipv6:pton(ip))
   end
   return id, mac, t
end

local fib = {} --{session_id = {dest_mac = {dest_ip1, ...}}}

local function update_fib_line(_, s)
   local id, mac, ips = parse_fib_line(s)
   local vlan = fib[id]
   if not vlan then
      vlan = {}
      fib[id] = vlan
   end
   vlan[mac] = ips

   if DEBUG then
      local t = {}
      for i, ip in ipairs(ips) do
         t[i] = ipv6:ntop(ip)
      end
      print('added ',
         string.format('0x%04x', id),
         lib.hexdump(mac):gsub(' ', ':'),
         table.concat(t, ', '))
   end
end

local function lookup_fib(id, mac)
   return fib[id] and fib[id][mac]
end

--L2TPv3/IPv6 frame format ---------------------------------------------------

local l2tp_ct = ffi.typeof[[
struct {

   // ethernet
   char     dmac[6];
   char     smac[6];
   uint16_t ethertype;

   // ipv6
   uint32_t flow_id; // version, tc, flow_id
   int16_t  payload_length;
   int8_t   next_header;
   uint8_t  hop_limit;
   char     src_ip[16];
   char     dst_ip[16];

   // l2tp
   uint32_t session_id;
   char     cookie[8];

   // tunneled ethernet frame
   char l2tp_dmac[6];
   char l2tp_smac[6];

} __attribute__((packed)) *
]]

local l2tp_ct_size = ffi.sizeof(l2tp_ct)

local function macstr(mac)
   local mac = ffi.string(mac, 6)
   return lib.hexdump(mac):gsub(' ', ':')
end

local function ip6str(ip6)
   return ipv6:ntop(ip6)
end

local function l2tp_dump(p, text)
   local p = ffi.cast(l2tp_ct, p.data)
   if lib.htons(p.ethertype) == 0x86dd and p.next_header == 115 then
      local sessid = string.format('%04x', lib.ntohl(p.session_id))
      print('L2TP: '..text..' [0x'..sessid..'] '..
         macstr(p.smac)..','..ip6str(p.src_ip)..' -> '..
         macstr(p.dmac)..','..ip6str(p.dst_ip)..
         ' ['..macstr(p.l2tp_smac)..' -> '..macstr(p.l2tp_dmac)..']')
   else
      print('INVALID: ', string.format('%04x', lib.htons(p.ethertype)), p.next_header)
   end
end

local function l2tp_parse(p)
   if p.length < l2tp_ct_size then return end
	local p = ffi.cast(l2tp_ct, p.data)
   if lib.htons(p.ethertype) ~= 0x86dd then return end
	if p.next_header ~= 115 then return end
	local sessid = lib.ntohl(p.session_id)
	local l2tp_dmac = ffi.string(p.l2tp_dmac, 6)
	return sessid, l2tp_dmac
end

local function l2tp_update(p, dest_ip)
   local p = ffi.cast(l2tp_ct, p.data)
   ffi.copy(p.src_ip, LOCAL_IP, 16)
   ffi.copy(p.dst_ip, dest_ip, 16)
end

--data plane -----------------------------------------------------------------

local Lisper = {}

function Lisper:new (t)
   return setmetatable({_lookup = t.lookup}, {__index = self})
end

function Lisper:_route (p, tx)
   local sessid, dmac = l2tp_parse(p)
   if not sessid then return true end --invalid packet
   local ips = self._lookup(sessid, dmac)
   if ips then
      if link.nwritable(tx) < #ips then return end --dest. ringbuffer full
      for i=1,#ips do
         local p = packet.clone(p)
         l2tp_update(p, ips[i])
         link.transmit(tx, p)
      end
   else
      local p = packet.clone(p)
      --TODO: punt
   end
   return true
end

function Lisper:push ()
   local rx = self.input.rx
   local tx = self.output.tx
   if rx == nil or tx == nil then return end
   while not link.empty(rx) do
      local p = link.peek(rx)
      if self:_route(p, tx) then
         packet.free(link.receive(rx))
      else
         --dest. ringbuffer full, we'll try again on the next push
         break
      end
   end
end

--packet punting -------------------------------------------------------------

local PuntQueue = {}

function PuntQueue:new ()
   return {}
end

--program wiring -------------------------------------------------------------

local intercept = {}

function intercept:new(name)
   return setmetatable({text = name}, {__index = self})
end

function intercept:push ()
   local rx = self.input.rx
   local tx = self.output.tx
   if rx == nil or tx == nil then return end
   while not link.empty(rx) do
      local p = link.receive(rx)
      l2tp_dump(p, self.text)
      link.transmit(tx, p)
   end
end

function run (args)

   parse_args(args)

   local c = config.new()

   --data plane
   config.app(c, "lisper", Lisper, {lookup = lookup_fib})
   config.app(c, "nd", nd.nd_light, {
      local_mac = LOCAL_MAC,
      local_ip = LOCAL_IP,
      next_hop = NEXT_HOP_IP,
   })
   config.app(c, "data", raw.RawSocket, NET_IF)
   config.link(c, "lisper.tx -> nd.north")
   config.link(c, "nd.north -> lisper.rx")
   if DEBUG then
      config.app(c, "intercept_out", intercept, '>')
      config.app(c, "intercept_in", intercept, '<')
      config.link(c, "nd.south -> intercept_out.rx")
      config.link(c, "intercept_out.tx -> data.rx")
      config.link(c, "data.tx -> intercept_in.rx")
      config.link(c, "intercept_in.tx -> nd.south")
   else
      config.link(c, "nd.south -> data.rx")
      config.link(c, "data.tx -> nd.south")
   end

   --control plane
   config.app(c, "ctl", unix.UnixSocket, {filename = CONTROL_SOCK, listen = true})
   config.app(c, "fib", lines.Lines, {callback = update_fib_line})
   config.link(c, "ctl.tx -> fib.rx")

   --punting
   config.app(c, "puntq", PuntQueue)
   config.app(c, "punt", raw.RawSocket, PUNT_IF)
   config.link(c, "puntq.tx -> punt.rx")

   engine.configure(c)

   print("LISPER started.")
   print("  network interface : "..NET_IF)
   print("  punt interface    : "..PUNT_IF)
   print("  control socket    : "..CONTROL_SOCK)
   print("  local IP          : "..ip6str(LOCAL_IP))
   print("  local MAC         : "..macstr(LOCAL_MAC))
   print("  next hop IP       : "..ip6str(NEXT_HOP_IP))

   engine.main({report = {showlinks=true}})

end
