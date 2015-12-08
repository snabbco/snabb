module(..., package.seeall)

local ffi      = require("ffi")
local lib      = require("core.lib")
local packet   = require("core.packet")
local usage    = require("program.lisper.README_inc")
local ipv6     = require("lib.protocol.ipv6")
local ethernet = require("lib.protocol.ethernet")
local unix     = require("apps.socket.unix")
local raw      = require("apps.socket.raw")
local nd       = require("apps.ipv6.nd_light")
local pcap     = require("apps.pcap.pcap")
local basic    = require("apps.basic.basic_apps")
local intel    = require("apps.intel.intel_app")
local trunk    = require("apps.802_1q.trunk")
local json     = require("lib.json")

--utils ----------------------------------------------------------------------

local function assert(v, ...) --assert overload because
   if v then return v, ... end
   error(tostring((...)), 2)
end

local function parsehex(s)
   return s and s ~= "" and (s:gsub("[0-9a-fA-F][0-9a-fA-F]", function(cc)
     return char(tonumber(cc, 16))
   end))
end

local function macstr(mac)
   local mac = ffi.string(mac, 6)
   return lib.hexdump(mac):gsub(" ", ":")
end

local function ip6str(ip6)
   return ipv6:ntop(ip6)
end

local _ = string.format

--config ---------------------------------------------------------------------

local DEBUG = os.getenv"LISPER_DEBUG" --if set, print packets to stdout
local MODE  = os.getenv"LISPER_MODE" --if set to "record" then record packets to pcap files

local conf

local function update_config(s)
   local t = assert(json.decode(s)) --see dev-env/lisper.conf for the format
   t.interfaces = t.interfaces or {}
   --map interfaces by name
   for i,iface in ipairs(t.interfaces) do
      t.interfaces[iface.name] = iface
   end
   --associate vlans to interfaces
   if t.vlans then
      for i,vlan in ipairs(t.vlans) do
         local iface = assert(t.interfaces[vlan.interface],
            "invalid interface "..vlan.interface.." for vlan "..vlan.name)
         iface.vlans = iface.vlans or {}
         table.insert(iface.vlans, vlan)
         vlan.mac = vlan.mac or iface.mac
         vlan.ip = vlan.ip or iface.ip
         vlan.gateway = vlan.gateway or iface.gateway
      end
   end
   --associate lispers with interfaces
   if t.lispers then
      for i,t in ipairs(t.lispers) do
      end
   end
   if t.local_networks then
      for i,t in ipairs(t.local_networks) do
      end
   end
   conf = t
end

--fib ------------------------------------------------------------------------

local fib = {} --{iid = {dest_mac = {rloc1, ...}}}

local function update_fib(s)
   local t = assert(json.decode(s))
   for k,v in pairs(t) do
      local iid = assert(k["instance-id"])
      local dt = {}
      fib[iid] = dt
      local eid_prefix = assert(k["eid-prefix"])
      local mac = eid_prefix:gsub("/d+$", "") --MAC/48
      local mac = ethernet:pton(mac)
      local rt = {}
      dt[mac] = rt
      local rlocs = k.rlocs or k.rles
      if #rlocs > 0 then
         for i,t in ipairs(rlocs) do
            local dt = {}
            table.insert(rt, dt)
            dt.ip = assert(t.rloc or t.rle)
            dt.priority = tonumber(t.priority)
            dt.weight = tonumber(t.weight)
            dt.key = parsehex(t.key)
         end
      end
   end
end

local function lookup_fib(iid, mac)
   return fib[iid] and fib[id][mac]
end

--punting --------------------------------------------------------------------

local punt = {} --{{mac=,name=,},...}

local function punt_mac(mac, ifname)
   table.insert(punt, {mac = mac, ifname = ifname})
end

local function get_punt_message()
   local t = table.remove(punt)
   if not t then return end
   return _('{"eid-prefix" : "%s", "interface" : "%s"}', macstr(t.mac), t.ifname)
end

--L2TPv3/IPv6 frame format ---------------------------------------------------

local l2tp_ct = ffi.typeof[[
   struct {
      // ethernet
      char     dmac[6];
      char     smac[6];
      uint16_t ethertype; // dd:86 = ipv6

      // ipv6
      uint32_t flow_id; // version, tc, flow_id
      int16_t  payload_length;
      int8_t   next_header; // 115 = l2tpv3
      uint8_t  hop_limit;
      char     src_ip[16];
      char     dst_ip[16];

      // l2tp
      uint32_t session_id;
      char     cookie[8];

      // tunneled ethernet frame
      char l2tp_dmac[6];
      char l2tp_smac[6];

   } __attribute__((packed))
   ]]
local l2tp_ct_size = ffi.sizeof(l2tp_ct)
local l2tp_ctp = ffi.typeof("$*", l2tp_ct)

local function l2tp_parse(p)
   if p.length < l2tp_ct_size then return end
   local p = ffi.cast(l2tp_ctp, p.data)
   if p.ethertype ~= 0xdd86 then return end --not ipv6
   if p.next_header ~= 115 then return end --not l2tpv3
   local sessid = lib.ntohl(p.session_id)
   local l2tp_dmac = ffi.string(p.l2tp_dmac, 6)
   return sessid, l2tp_dmac
end

local function l2tp_update(p, dest_ip, local_ip)
   local p = ffi.cast(l2tp_ctp, p.data)
   ffi.copy(p.src_ip, local_ip, 16)
   ffi.copy(p.dst_ip, dest_ip, 16)
end

--frame dumper ---------------------------------------------------------------

local function l2tp_dump(p, text)
   local p = ffi.cast(l2tp_ctp, p.data)
   if not (p.length >= l2tp_ct_size
      and p.ethertype == 0xdd86
      and p.next_header == 115)
   then
      print("INVALID: ", _("%04x", lib.htons(p.ethertype)), p.next_header)
   end
   local sessid = _("%04x", lib.ntohl(p.session_id))
   print("L2TP: "..text.." [0x"..sessid.."] "..
      macstr(p.smac)..","..ip6str(p.src_ip).." -> "..
      macstr(p.dmac)..","..ip6str(p.dst_ip)..
      " ["..macstr(p.l2tp_smac).." -> "..macstr(p.l2tp_dmac).."]")
end

local L2TP_Dump = {}

function L2TP_Dump:new(name)
   return setmetatable({text = name}, {__index = self})
end

function L2TP_Dump:push()
   local rx = self.input.rx
   local tx = self.output.tx
   if rx == nil or tx == nil then return end
   while not link.empty(rx) do
      local p = link.receive(rx)
      l2tp_dump(p, self.text)
      link.transmit(tx, p)
   end
end

--control plane --------------------------------------------------------------

local Ctl = {}

function Ctl:new()
   return setmetatable({}, {__index = self})
end

function Ctl:push()
   local rx = self.input.rx
   if rx == nil then return end
   while not link.empty(rx) do
      local p = link.receive(rx)
      local s = ffi.string(p.data, p.length)
      update_fib(s)
   end
end

local Punt = {}

function Punt:new()
   return setmetatable({}, {__index = self})
end

function Punt:pull()
   local tx = self.output.tx
   if tx == nil then return end
   while not link.full(tx) do
      local s = get_punt_message()
      if not s then break end
      link.transmit(rx, s)
   end
end

--data plane -----------------------------------------------------------------

local function rloc_interface(rloc)
   --TODO
end

local function route_packet(p, rxname, txports)
   local iid, dmac = l2tp_parse(p)
   if not idd then return true end --invalid packet
   local rlocs = lookup_fib(iid, dmac)
   if rlocs then
      --check if all rloc interfaces have room for the packet
      for i=1,#rlocs do
         local txname = rloc_interface(rlocs[i])
         local tx = txports[txname]
         if link.full(tx) then return end --dest. buffer full
      end
      for i=1,#rlocs do
         local txname, local_ip = rloc_interface(rlocs[i])
         local tx = txports[txname]
         local p = packet.clone(p)
         l2tp_update(p, rlocs[i].ip, local_ip)
         link.transmit(tx, p)
      end
   else
      punt_mac(dmac, rxname)
   end
   return true
end

local Lisper = {}

function Lisper:new()
   return setmetatable({}, {__index = self})
end

function Lisper:push()
   for rxname, rx in pairs(self.input) do
      while not link.empty(rx) do
         local p = link.peek(rx)
         if route_packet(p, rxname, self.output) then
            packet.free(link.receive(rx))
         else
            --dest. ringbuffer full, we'll try again on the next push
            break
         end
      end
   end
end

--program args ---------------------------------------------------------------

local long_opts = {
   ["config-file"] = "c",
   help = "h",
}

local opt = {}

function opt.h(arg)
   print(usage)
   main.exit(0)
end

function opt.c(arg)
   local s = assert(lib.readfile(arg, "*a"), "file not found: "..arg)
   s = s:gsub("//.-([\r\n])", "%1") --strip comments
   update_config(s)
end

local function parse_args(args)
   return lib.dogetopt(args, opt, "hc:", long_opts)
end

--main loop ------------------------------------------------------------------

function run(args)

   parse_args(args)

   local c = config.new()

   --control plane

   config.app(c, "ctl", Ctl)
   config.app(c, "ctl_sock", unix.UnixSocket, {
      filename = conf.control_sock,
      listen = true,
      mode = "packet",
   })
   config.link(c, "ctl_sock.tx -> ctl.rx")

   config.app(c, "punt", Punt)
   config.app(c, "punt_sock", unix.UnixSocket, {
      filename = conf.punt_sock,
      listen = false,
      mode = "packet",
   })
   config.link(c, "punt.tx -> punt_sock.rx")

   --data plane

   config.app(c, "lisper", Lisper)

   for i,iface in ipairs(conf.interfaces) do

      local ifname = iface.name

      if iface.pci then
         config.app(c, "if_"..ifname, intel.Intel82599, {
            pciaddr = iface.pci,
            macaddr = iface.mac,
         })
      else
         config.app(c, "if_"..ifname, raw.RawSocket, ifname)
      end

      if iface.vlans then

         local ports = {}
         for i,vlan in ipairs(iface.vlans) do
            ports[vlan.id] = vlan.name
         end
         config.app(c, "trunk_"..ifname, trunk.Trunk, ports)

         config.link(c, _("trunk_%s.trunk -> if_%s.rx", ifname, ifname))
         config.link(c, _("if_%s.tx -> trunk_%s.trunk", ifname, ifname))

         for i,vlan in ipairs(iface.vlans) do

            local vname = vlan.name

            if vlan.gateway then -- if -> trunk -> nd -> lisper

               config.app(c, "nd_"..vname, nd.nd_light, {
                  local_mac = vlan.mac,
                  local_ip = vlan.ip,
                  next_hop = vlan.gateway,
               })
               config.link(c, _("nd_%s.south -> trunk_%s.%s", vname, ifname, vname))
               config.link(c, _("trunk_%s.%s -> nd_%s.south", ifname, vname, vname))

               config.link(c, _("lisper.%s -> nd_%s.north", vname, vname))
               config.link(c, _("nd_%s.north -> lisper.%s", vname, vname))

            else -- if -> trunk -> lisper

               config.link(c, _("lisper.%s -> trunk_%s.%s", vname, ifname, vname))
               config.link(c, _("trunk_%s.%s -> lisper.%s", ifname, vname, vname))

            end

         end

      elseif iface.gateway then -- if -> nd -> lisper

         config.app(c, "nd_"..ifname, nd.nd_light, {
            local_mac = iface.mac,
            local_ip = iface.ip,
            next_hop = iface.gateway,
         })
         config.link(c, _("nd_%s.south -> if_%s.rx", ifname, ifname))
         config.link(c, _("if_%s.tx -> nd_%s.south", ifname, ifname))

         config.link(c, _("lisper.%s -> nd_%s.north", ifname, ifname))
         config.link(c, _("nd_%s.north -> lisper.%s", ifname, ifname))

      else -- if -> lisper

         config.link(c, _("lisper.%s -> if_%s.rx", ifname, ifname))
         config.link(c, _("if_%s.tx -> lisper.%s", ifname, ifname))

      end

   end

   engine.configure(c)

   print(config.graphviz(c))

   engine.main({report = {showlinks=true}})

end
