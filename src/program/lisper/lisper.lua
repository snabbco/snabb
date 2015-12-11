module(..., package.seeall)

local ffi      = require("ffi")
local app      = require("core.app")
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

local htons = lib.htons
local htonl = lib.htonl
local ntohl = lib.ntohl
local getenv = lib.getenv
local hexdump = lib.hexdump

local function assert(v, ...) --assert overload because
   if v then return v, ... end
   error(tostring((...) or "Assertion failed"), 2)
end

local function parsehex(s)
   return (s:gsub("[0-9a-fA-F][0-9a-fA-F]", function(cc)
     return string.char(tonumber(cc, 16))
   end))
end

local function parsemac(s)
   local s = parsehex(s:gsub("[%:%s%-]", ""))
   assert(#s == 6)
   return s
end

local function parseip6(s)
   return ffi.string(ipv6:pton(s), 16)
end

local function macstr(mac)
   local mac = ffi.string(mac, 6)
   return hexdump(mac):gsub(" ", ":"):lower()
end

local function macstr2(mac)
   local mac = macstr(mac):gsub(":", "")
   return mac:sub(1, 6).."-"..mac:sub(7)
end

local function ip6str(ip6)
   return ipv6:ntop(assert(ip6))
end

local function padhex(s, n) --pad a hex string to a fixed number of bytes
   return ("0"):rep(n*2 - #s)..s
end

local function parsecookie(cookie) --8-byte L2TPv3 cookie given in hex
   return parsehex(padhex(cookie, 8))
end

local function cookiestr(cookie)
   local s = hexdump(ffi.string(cookie, 8)):gsub(" ", "")
   return s == ("0"):rep(16) and "0" or s
end

local _ = string.format

--get the value of a table field, and if the field is not present in the
--table, create it as an empty table, and return it.
local function attr(t, k)
	local v = t[k]
	if v == nil then
		v = {}
		t[k] = v
	end
	return v
end

local broadcast_mac = parsemac("ffffff-ffffff")
local empty_mac     = parsemac("000000-000000")

--config ---------------------------------------------------------------------

local DEBUG = getenv"LISPER_DEBUG" --if set, print packets to stdout
local MODE  = getenv"LISPER_MODE"  --if set to "record" then record packets to pcap files

--phy_t:         {name=s, mac=mac, pci=s, vlans={vlan1_t, ...}, exits={exit1_t,...}}
--vlan_t:        {name=s, mac=mac, id=n, interface=phy_t, exits={exit1_t,...}}
--if_t:          phy_t|vlan_t
--exit_t:        {ip=ipv6, interface=if_t, next_hop=ip6[, next_hop_mac=s]}
--loc_t:         eth_loc_t|l2tp_loc_t|lisper_loc_t
--eth_loc_t:     {type="ethernet", interface=if_t}
--l2tp_loc_t:    {type="l2tpv3", ip=ip6, session_id=n, cookie=s, exit=exit_t}
--lisper_loc_t:  {type="lisper", ip=ip6, p=n, w=n, key=s, exit=exit_t}
local conf     --{control_sock=s, punt_sock=s}
local phys     --{ifname -> phy_t}
local vlans    --{id -> vlan_t}
local ifs      --{ifname -> if_t}
local exits    --{exitname -> exit_t}
local eths     --{ifname -> {iid=n, loc=eth_loc_t}}
local l2tps    --{sesson_id -> {cookie -> {iid=n, loc=l2tp_loc_t}}}
local locs     --{iid -> {dest_mac -> {loc1_t, ...}}}
local lispers  --{ipv6 -> exit_t}

--see dev-env/lisper.conf for the format of s.
local function update_config(s)
   local t = assert(json.decode(s))

   conf = {}
   phys = {}
   vlans = {}
   ifs = {}
   exits = {}
   eths = {}
   l2tps = {}
   locs = {}
   lispers = {}

   --globals
   conf.control_sock = t.control_sock
   conf.punt_sock = t.punt_sock

   --map physical interfaces
   if t.interfaces then
      for i,iface in ipairs(t.interfaces) do
         assert(not ifs[iface.name], "duplicate interface name: "..iface.name)
         local phy_t = {
            name = iface.name,
            pci = iface.pci,
            mac = parsemac(iface.mac),
            vlans = {},
            exits = {},
         }
         phys[iface.name] = phy_t
         ifs[iface.name] = phy_t
      end
   end

   --map 802.1Q interfaces
   if t.vlans then
      for i,vlan in ipairs(t.vlans) do
         local iface = assert(phys[vlan.interface],
            "invalid interface "..vlan.interface.." for vlan "..vlan.name)
         assert(not ifs[iface.name], "duplicate interface name: "..iface.name)
         local vlan_t = {
            name = vlan.name,
            mac = parsemac(vlan.mac or iface.mac),
            id = vlan.id,
            interface = iface,
            exits = {},
         }
         table.insert(iface.vlans, vlan_t)
         vlans[vlan.id] = vlan_t
         ifs[vlan.name] = vlan_t
      end
   end

   --map ipv6 exit points
   if t.exits then
      for i,t in ipairs(t.exits) do
         local ip = parseip6(t.ip)
         local iface = assert(ifs[t.interface], "invalid interface "..t.interface)
         local exit_t = {
            name = t.name,
            ip = ip,
            interface = iface,
            next_hop = t.next_hop and parseip6(t.next_hop),
            next_hop_mac = t.next_hop_mac and parsemac(t.next_hop_mac),
         }
         exits[t.name] = exit_t
         table.insert(iface.exits, exit_t)
      end
   end

   --map local L2 networks and l2tp-tunneled networks
   if t.local_networks then
      for i,net in ipairs(t.local_networks) do
         local context = "local network #"..i
         if net.type and net.type:lower() == "l2tpv3" then
            local sid = assert(net.session_id, "session_id missing on "..context)
            local cookie = parsecookie(net.cookie)
            local ip = parseip6(net.ip)
            local exit = exits[net.exit]
            assert(exit, "invalid exit "..net.exit)
            local loc = {
               type = "l2tpv3",
               ip = ip,
               session_id = sid,
               cookie = cookie,
               exit = exit,
            }
            attr(l2tps, sid)[cookie] = {iid = net.iid, loc = loc}
            local blocs = attr(attr(locs, net.iid), broadcast_mac)
            table.insert(blocs, loc)
         else
            local iface = assert(ifs[net.interface], "invalid interface "..net.interface)
            local loc = {
               type = "ethernet",
               interface = iface,
            }
            eths[net.interface] = {iid = net.iid, loc = loc}
            local blocs = attr(attr(locs, net.iid), broadcast_mac)
            table.insert(blocs, loc)
         end
      end
   end

   --map lispers
   if t.lispers then
      for i,t in ipairs(t.lispers) do
         local ip = parseip6(t.ip)
         local exit = exits[t.exit]
         assert(exit, "invalid exit "..t.exit)
         lispers[ip] = exit
      end
   end
end

local log_learn --fw. decl.

--see "Map-Cache Population IPC Interface" section in dt-l2-overlay.txt
--for the format of s.
local function update_fib(s)
   local t = assert(json.decode(s))
   local iid = assert(t["instance-id"])
   local dt = attr(locs, iid)
   local eid_prefix = assert(t["eid-prefix"])
   local mac = eid_prefix:gsub("/%d+$", "") --MAC/48
   local mac = parsemac(mac)
   local rt = {}
   if mac == broadcast_mac then
      --when learning about a broadcast address we learn which remote lispers
      --are configured to transport a certain iid, but we must preserve
      --the statically configured locations.
      local cur_locs = dt[mac]
      if cur_locs then
         for i,loc in ipairs(cur_locs) do
            if loc.type ~= "lisper" then
               table.insert(rt, loc)
            end
         end
      end
   end
   dt[mac] = rt
   local rlocs = t.rlocs or t.rles
   if rlocs and #rlocs > 0 then
      for i,t in ipairs(rlocs) do
         local rloc = assert(t.rloc or t.rle)
         local ip = parseip6(rloc)
         local exit = lispers[ip]
         assert(exit, "invalid rloc "..rloc)
         local key = t.key and t.key ~= "" and parsehex(t.key)
         local p = tonumber(t.priority)
         local w = tonumber(t.weight)
         local loc = {
            type = "lisper",
            ip = ip,
            p = p,
            w = w,
            key = key,
            exit = exit,
         }
         table.insert(rt, loc)
         log_learn(iid, mac, loc)
      end
   end
end

--punting queue --------------------------------------------------------------

local punt = {} --{{mac=,name=}, ...}

local function punt_mac(mac, ifname)
   table.insert(punt, {mac = mac, ifname = ifname})
end

local function get_punt_message()
   local t = table.remove(punt)
   if not t then return end
   return _('{"eid-prefix" : "%s", "interface" : "%s"}', macstr(t.mac), t.ifname)
end

--data plane -----------------------------------------------------------------

local l2tp_ct = ffi.typeof[[
   struct {
      // ethernet
      char     dmac[6];
      char     smac[6];
      uint16_t ethertype; // dd:86 = ipv6

      // ipv6
      uint32_t flow_id; // version, tc, flow_id
      int16_t  payload_length;
      int8_t   next_header; // 115 = L2TPv3
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

local function parse_eth(p)
   if p.length < 12 then return end
   local p = ffi.cast(l2tp_ctp, p.data)
   local smac = ffi.string(p.smac, 6)
   local dmac = ffi.string(p.dmac, 6)
   return smac, dmac, 0
end

local function parse_l2tp(p)
   if p.length < l2tp_ct_size then return end
   local p = ffi.cast(l2tp_ctp, p.data)
   if p.ethertype ~= 0xdd86 then return end --not IPv6
   if p.next_header ~= 115 then return end --not L2TPv3
   local src_ip = ffi.string(p.src_ip, 16)
   local sid = ntohl(p.session_id)
   local cookie = ffi.string(p.cookie, 8)
   local l2tp_smac = ffi.string(p.l2tp_smac, 6)
   local l2tp_dmac = ffi.string(p.l2tp_dmac, 6)
   return src_ip, sid, cookie, l2tp_smac, l2tp_dmac, 66
end

local function copy_payload(srcp, src_payload_offset, dst_payload_offset)
   local dstp = packet.allocate()
   local payload_length = srcp.length - src_payload_offset
   ffi.copy(
      dstp.data + dst_payload_offset,
      srcp.data + src_payload_offset,
      payload_length)
   dstp.length = dst_payload_offset + payload_length
   return dstp
end

local function format_eth(srcp, payload_offset)
   return copy_payload(srcp, payload_offset, 0)
end

local function format_l2tp(srcp, payload_offset, smac, dmac, src_ip, dst_ip, sid, cookie)
   local dstp = copy_payload(srcp, payload_offset, 66)
   local p = ffi.cast(l2tp_ctp, dstp.data)
   ffi.copy(p.smac, smac, 6)
   ffi.copy(p.dmac, dmac, 6)
   p.ethertype = 0xdd86 --ipv6
   p.flow_id = 0x60 --ipv6
   local plen = srcp.length - payload_offset
   p.payload_length = htons(plen + 12) --payload + L2TPv3 header
   p.next_header = 115 --L2TPv3
   p.hop_limit = 64 --default
   ffi.copy(p.src_ip, src_ip, 16)
   ffi.copy(p.dst_ip, dst_ip, 16)
   p.session_id = htonl(sid)
   ffi.copy(p.cookie, cookie, 8)
   return dstp
end

local function log_eth(text, pk, ifname)
   if not DEBUG then return end
   local p = ffi.cast(l2tp_ctp, pk.data)

   if pk.length < 12 then
      print(_("ETH  %-4s %s (%4d): INVALID", ifname, text, pk.length))
      return
   end

   print(_("ETH  %-4s %s (%4d): [%s -> %s]",
      ifname, text, pk.length, macstr2(p.smac), macstr2(p.dmac)))
end

local function log_l2tp(text, pk, ifname)
   if not DEBUG then return end
   local p = ffi.cast(l2tp_ctp, pk.data)

   local valid =
      pk.length >= l2tp_ct_size
      and p.ethertype == 0xdd86
      and p.next_header == 115

   if not valid then
      print("L2TP %-4s %s (%4d): INVALID: ethertype: 0x%04x, next_header: %d",
         ifname, text, pk.length, htons(p.ethertype), p.next_header)
      return
   end

   print(_("L2TP %-4s %s (%4d): [%s -> %s] 0x%04x/%s %s,%s -> %s,%s",
      ifname, text, pk.length,
      macstr2(p.l2tp_smac),
      macstr2(p.l2tp_dmac),
      ntohl(p.session_id),
      cookiestr(p.cookie),
      macstr2(p.smac), ip6str(p.src_ip),
      macstr2(p.dmac), ip6str(p.dst_ip)))
end

function log_learn(iid, smac, sloc)
   if not DEBUG then return end
   print(_("LEARN: [%d] %s <- type: %s, %s", iid, macstr2(smac), sloc.type,
      sloc.type == "ethernet"
         and ip6str(sloc.interface.name)
      or sloc.type == "l2tpv3"
         and _("ip: %s, session_id: 0x%04x, cookie: %s",
            ip6str(sloc.ip),
            sloc.session_id,
            cookiestr(sloc.cookie)
         )
      or sloc.type == "lisper"
         and _("ip: %s%s%s%s", ip6str(sloc.ip),
            sloc.p and ", p: "..sloc.p or "",
            sloc.w and ", w: "..sloc.w or "",
            sloc.key and ", key: "..hexdump(sloc.key):gsub(" ", "") or "")
   ))
end

local function route_packet(p, rxname, txports)

   --step #1: find the iid and source location of the packet.
   --NOTE: smac and dmac are the MACs of the payload ethernet frame!
   local iid, sloc, smac, dmac, payload_offset
   local t = eths[rxname]
   if t then --packet came from a local ethernet
      iid, sloc = t.iid, t.loc
      smac, dmac, payload_offset = parse_eth(p)
      if not smac then return end --invalid packet
      log_eth("<<<", p, rxname)
   else --packet came from a l2tp tunnel or a lisper
      local src_ip, session_id, cookie
      src_ip, session_id, cookie, smac, dmac, payload_offset = parse_l2tp(p)
      if not src_ip then return end --invalid packet
      if lispers[src_ip] then --packet came from a lisper
         iid = session_id --iid comes in the session_id field, cookie is ignored
      else --packet came from a l2tp tunnel
         local t = l2tps[session_id] and l2tps[session_id][cookie]
         log_l2tp("<<<", p, rxname)
         if not t then return end --invalid packet: bad l2tp config
         iid, sloc = t.iid, t.loc
      end
   end
   local locs = locs[iid] --contextualize locations

   --step #2: remember the location of the smac and punt it if it's new
   if sloc then --didn't come from a lisper
      local slocs = locs[smac]
      if not slocs or slocs[1] ~= sloc then
         locs[smac] = {sloc}
         log_learn(iid, smac, sloc)
         punt_mac(smac, rxname)
      end
   end

   --step #3: find the location(s) of the dest. mac and send the payload
   --to it/them.  We can have multiple locations only if they're all of
   --type "lisper" (i.e. multihoming), or if the dmac is the broadcast mac,
   --or if the dmac is unknown (in which case we use the broadcast mac).
   local dlocs = locs[dmac] or locs[broadcast_mac]
   for i=1,#dlocs do
      local loc = dlocs[i]
      local dp, tx
      if loc.type == "ethernet" then
         dp = format_eth(p, payload_offset)
         local txname = loc.interface.name
         tx = txports[txname]
         log_eth(">>>", dp, txname)
      elseif loc.type == "l2tpv3" then
         dp = format_l2tp(p, payload_offset,
            loc.exit.interface.mac,
            loc.exit.next_hop_mac or empty_mac, --replaced by nd_light
            loc.exit.ip,
            loc.ip,
            loc.session_id,
            loc.cookie)
         local txname = loc.exit.interface.name
         tx = txports[txname]
         log_l2tp(">>>", dp, txname)
      elseif not sloc then
         return --came from a lisper, drop it to prevent ringing
      elseif loc.type == "lisper" then
         dp = format_l2tp(p, payload_offset,
            loc.exit.interface.mac,
            loc.exit.next_hop_mac or empty_mac, --replaced by nd_light
            loc.exit.ip,
            loc.ip,
            iid,
            "\0\0\0\0\0\0\0\0")
         local txname = loc.exit.interface.name
         tx = txports[txname]
         log_l2tp(")))", dp, txname)
      end
      if not link.full(tx) then
         link.transmit(tx, dp)
      end
   end
end

--data processing apps -------------------------------------------------------

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
      local p = packet.allocate()
      p.length = #s
      ffi.copy(p.data, s)
      link.transmit(tx, p)
   end
end

local Lisper = {}

local ports = {} --{ifname1,...}

function Lisper:new()
   --make a list of ports connected to lisper for faster iteration
   for ifname,iface in pairs(ifs) do
      if not iface.vlans or #iface.vlans == 0 then
         table.insert(ports, ifname)
      end
   end
   return setmetatable({}, {__index = self})
end

function Lisper:push()
   for i=1,#ports do
      local rxname = ports[i]
      local rx = self.input[rxname]
      while not link.empty(rx) do
         local p = link.receive(rx)
         route_packet(p, rxname, self.output)
         packet.free(p)
      end
   end
end

local Dumper = {}

function Dumper:new(text)
   return setmetatable({text = text}, {__index = self})
end

function Dumper:push()
   local rx = self.input.rx
   local tx = self.output.tx
   if rx == nil or tx == nil then return end
   while not link.empty(rx) do
      local p = link.receive(rx)
      l2tp_dump(p, self.text)
      link.transmit(tx, p)
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

   for ifname,iface in pairs(phys) do

      if iface.pci then
         config.app(c, "if_"..ifname, intel.Intel82599, {
            pciaddr = iface.pci,
            macaddr = macstr(iface.mac),
         })
      else
         config.app(c, "if_"..ifname, raw.RawSocket, ifname)
      end

      local function needs_nd(exits)
         if #exits == 0 then return end
         assert(#exits == 1, "multiple exits per interface not supported")
         return not exits[1].next_hop_mac
      end

      if #iface.vlans > 0 then

         local ports = {}
         for i,vlan in ipairs(iface.vlans) do
            ports[vlan.id] = vlan.name
         end
         config.app(c, "trunk_"..ifname, trunk.Trunk, ports)

         config.link(c, _("trunk_%s.trunk -> if_%s.rx", ifname, ifname))
         config.link(c, _("if_%s.tx -> trunk_%s.trunk", ifname, ifname))

         for i,vlan in ipairs(iface.vlans) do

            local vname = vlan.name

            if needs_nd(vlan.exits) then

               local exit = vlan.exits[1]

               config.app(c, "nd_"..vname, nd.nd_light, {
                  local_mac = macstr(vlan.mac),
                  local_ip = ip6str(exit.ip),
                  next_hop = ip6str(exit.next_hop),
               })
               config.link(c, _("nd_%s.south -> trunk_%s.%s", vname, ifname, vname))
               config.link(c, _("trunk_%s.%s -> nd_%s.south", ifname, vname, vname))

               config.link(c, _("lisper.%s -> nd_%s.north", vname, vname))
               config.link(c, _("nd_%s.north -> lisper.%s", vname, vname))

            else -- phy -> trunk -> lisper

               config.link(c, _("lisper.%s -> trunk_%s.%s", vname, ifname, vname))
               config.link(c, _("trunk_%s.%s -> lisper.%s", ifname, vname, vname))

            end

         end

      elseif needs_nd(iface.exits) then -- phy -> nd -> lisper

         local exit = iface.exits[1]

         config.app(c, "nd_"..ifname, nd.nd_light, {
            local_mac = macstr(iface.mac),
            local_ip = ip6str(exit.ip),
            next_hop = ip6str(exit.next_hop),
         })

         config.link(c, _("nd_%s.south -> if_%s.rx", ifname, ifname))
         config.link(c, _("if_%s.tx -> nd_%s.south", ifname, ifname))

         config.link(c, _("lisper.%s -> nd_%s.north", ifname, ifname))
         config.link(c, _("nd_%s.north -> lisper.%s", ifname, ifname))

      else -- phy -> lisper

         config.link(c, _("lisper.%s -> if_%s.rx", ifname, ifname))
         config.link(c, _("if_%s.tx -> lisper.%s", ifname, ifname))

      end

   end

   engine.configure(c)

   print("Links:")
   for linkspec in pairs(c.links) do
      print("  "..linkspec)
   end
   print("Params:")
   for appname, app in pairs(app.app_table) do
      local s = ""
      local arg = c.apps[appname].arg
      if arg == "nil" then arg = nil end --TODO: fix core.config
      if type(arg) == "string" then
         s = arg
      elseif type(arg) == "table" then
         local t = {}
         for k,v in pairs(arg) do
            table.insert(t, _("\n    %-10s: %s", k, tostring(v)))
         end
         s = table.concat(t)
      end
      print(_("  %-12s: %s", appname, s))
   end

   engine.main({report = {showlinks=true}})

end
