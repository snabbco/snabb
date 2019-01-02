module(..., package.seeall)

local packet = require("core.packet")
local bit = require("bit")
local ffi = require("ffi")
local lib = require("core.lib")

local C = ffi.C
local receive, transmit = link.receive, link.transmit
local full, empty = link.full, link.empty
local cast = ffi.cast
local htons, htonl = lib.htons, lib.htonl
local ntohs, ntohl = htons, htonl

local default_encap = { default = "dot1q" }
Tagger = {
   config = {
      encapsulation = default_encap,
      tag = { required = true }
   }
}
Untagger = {
   config = {
      encapsulation = default_encap,
      tag = { required = true }
   }
}
VlanMux = {
   config = {
      encapsulation = default_encap,
   }
}

local tpids = { dot1q = 0x8100, dot1ad = 0x88A8 }
local o_ethernet_ethertype = 12
local uint32_ptr_t = ffi.typeof('uint32_t*')


-- build a VLAN tag consisting of 2 bytes of TPID followed by the TCI
-- field which in turns consists of PCP, DEI and VID (VLAN id). Both
-- PCP and DEI is always 0.  Inputs are in host byte-order, output is
-- in network byte order.
local function build_tag (vid, tpid)
   return htonl(bit.bor(bit.lshift(tpid, 16), vid))
end

-- pop a VLAN tag (4 byte of TPID and TCI) from a packet
function pop_tag (pkt)
   C.memmove(pkt.data + 4, pkt.data, o_ethernet_ethertype)
   return packet.shiftleft(pkt, 4)
end

-- push a VLAN tag onto a packet.  The tag is in network byte-order.
function push_tag (pkt, tag)
   local pkt = packet.shiftright(pkt, 4)
   C.memmove(pkt.data, pkt.data + 4, o_ethernet_ethertype)
   local payload = pkt.data + o_ethernet_ethertype
   cast(uint32_ptr_t, payload)[0] = tag
   return pkt
end

-- extract TCI (2 bytes) from packet, no check is performed to verify that the
-- packet is carrying a VLAN tag, if it's an untagged frame these bytes will be
-- Ethernet payload
function extract_tci(pkt)
   return ntohs(cast("uint16_t*", pkt.data + o_ethernet_ethertype + 2)[0])
end

-- extract VLAN id from TCI
function tci_to_vid (tci)
   return bit.band(tci, 0xFFF)
end

function new_aux (self, conf)
   local encap = conf.encapsulation
   if (type(encap) == "string") then
      self.tpid = tpids[encap]
      assert(self.tpid, "Unsupported encapsulation type "..encap)
   else
      assert(type(encap) == "number")
      self.tpid = encap
   end
   return self
end

function check_tag (tag)
   assert(tag >= 0 and tag < 4095, "VLAN tag "..tag.." out of range")
   return tag
end

function Tagger:new (conf)
   local o = setmetatable({}, {__index=Tagger})
   new_aux(o, conf)
   o.tag = build_tag(check_tag(conf.tag), o.tpid)
   return(o)
end

function Tagger:push ()
   local input, output = self.input.input, self.output.output
   local tag = self.tag
   for _=1,link.nreadable(input) do
      local pkt = receive(input)
      transmit(output, push_tag(pkt, tag))
   end
end

function Untagger:new (conf)
   local o = setmetatable({}, {__index=Untagger})
   new_aux(o, conf)
   o.tag = build_tag(check_tag(conf.tag), o.tpid)
   return(o)
end

function Untagger:push ()
   local input, output = self.input.input, self.output.output
   local tag = self.tag
   for _=1,link.nreadable(input) do
      local pkt = receive(input)
      local payload = pkt.data + o_ethernet_ethertype
      if cast(uint32_ptr_t, payload)[0] ~= tag then
         -- Incorrect VLAN tag; drop.
         packet.free(pkt)
      else
         transmit(output, pop_tag(pkt))
      end
   end
end

function VlanMux:new (conf)
   local o = setmetatable({}, {__index=VlanMux})
   return new_aux(o, conf)
end

function VlanMux:link ()
   local from_vlans, to_vlans = {}, {}
   for name, l in pairs(self.input) do
      if string.match(name, "vlan%d+") then
         local vid = check_tag(tonumber(string.sub(name, 5)))
         to_vlans[vid] = self.output[name]
         table.insert(from_vlans, { link = l, vid = vid })
      elseif name == "native" then
         to_vlans[0] = self.output.native
      elseif type(name) == "string" and name ~= "trunk" then
         error("invalid link name "..name)
      end
   end
   self.from_vlans = from_vlans
   self.to_vlans = to_vlans
end

function VlanMux:push ()
   local from, to = self.from_vlans, self.to_vlans
   local tpid = self.tpid
   local l_in = self.input.trunk
   assert(l_in)
   while not empty(l_in) do
      local p = receive(l_in)
      local ethertype = cast("uint16_t*", p.data
                                + o_ethernet_ethertype)[0]
      if ethertype == htons(tpid) then
         -- dig out TCI field
         local tci = extract_tci(p)
         local vid = tci_to_vid(tci)
         self:transmit(to[vid], pop_tag(p))
      else -- untagged, send to native output
         self:transmit(to[0], p)
      end
   end

   local l_out = self.output.trunk
   local i = 1
   while from[i] do
      local from = from[i]
      local l_in = from.link
      while not empty(l_in) do
         local p = receive(l_in)
         self:transmit(l_out, push_tag(p, build_tag(from.vid, tpid)))
      end
      i = i + 1
   end

   local l_in = self.input.native
   if l_in then
      while not empty(l_in) do
         self:transmit(l_out, receive(l_in))
      end
   end
end

-- transmit packet out interface if given interface exists, otherwise drop
function VlanMux:transmit(o, pkt)
   if o == nil then
      packet.free(pkt)
   else
      transmit(o, pkt)
   end
end

function test_tag_untag ()
   local pkt = packet.from_string(lib.hexundump([[
      02:aa:aa:aa:aa:aa 02:99:99:99:99:99 08 00 45 00
      00 54 43 58 40 00 40 01 7c 5c c0 a8 0d 28 ac 14
      01 10 08 00 9c d4 07 c0 00 01 bc fa e3 57 00 00
      00 00 f3 44 01 00 00 00 00 00 10 11 12 13 14 15
      16 17 18 19 1a 1b 1c 1d 1e 1f 20 21 22 23 24 25
      26 27 28 29 2a 2b 2c 2d 2e 2f 30 31 32 33 34 35
      36 37
   ]], 82))
   local vid = 0
   for i=0,15 do
      for j=0,255 do
         local tag = build_tag(vid, tpids.dot1q)
         pkt = push_tag(pkt, tag)
         local payload = pkt.data + o_ethernet_ethertype
         assert(cast(uint32_ptr_t, payload)[0] == tag)
         pkt = pop_tag(pkt)
         vid = vid + 1
      end
   end
   assert(vid == 4096)
   print("Sucessfully tagged/untagged all potential VLAN tags (0-4095)")
end

function selftest()
   local app = require("core.app")
   local basic_apps = require("apps.basic.basic_apps")

   local c = config.new()
   config.app(c, "vlan_source", basic_apps.Source)
   config.app(c, "vlan_mux", VlanMux)
   config.app(c, "trunk_sink", basic_apps.Sink)
   config.app(c, "trunk_source", basic_apps.Source)
   config.app(c, "native_source", basic_apps.Source)
   config.app(c, "native_sink", basic_apps.Sink)

   config.link(c, "vlan_source.output -> vlan_mux.vlan1")
   config.link(c, "vlan_mux.trunk -> trunk_sink.input")
   config.link(c, "trunk_source.output -> vlan_mux.trunk")
   config.link(c, "vlan_mux.native -> native_sink.input")
   config.link(c, "native_source.output -> vlan_mux.native")
   app.configure(c)
   app.main({duration = 1})

   print("vlan sent: "
            ..link.stats(app.app_table.vlan_source.output.output).txpackets)
   print("native sent: "
            ..link.stats(app.app_table.native_source.output.output).txpackets)
   print("trunk received: "
            ..link.stats(app.app_table.trunk_sink.input.input).rxpackets)
   print("trunk sent: "
            ..link.stats(app.app_table.trunk_source.output.output).txpackets)
   print("native received: "
            ..link.stats(app.app_table.native_sink.input.input).rxpackets)
   test_tag_untag()
end
