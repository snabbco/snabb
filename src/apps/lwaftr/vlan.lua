module(..., package.seeall)

local packet = require("core.packet")
local bit = require("bit")
local ffi = require("ffi")

local C = ffi.C
local receive, transmit = link.receive, link.transmit
local cast = ffi.cast

Tagger = {}
Untagger = {}

-- 802.1q
local dotq_tpid = 0x8100
local o_ethernet_ethertype = 12
local uint32_ptr_t = ffi.typeof('uint32_t*')

local function make_vlan_tag(tag)
   return ffi.C.htonl(bit.bor(bit.lshift(dotq_tpid, 16), tag))
end

function Tagger:new(conf)
   local o = setmetatable({}, {__index=Tagger})
   o.tag = make_vlan_tag(assert(conf.tag))
   return o
end

function Tagger:push ()
   local input, output = self.input.input, self.output.output
   local tag = self.tag
   for _=1,math.min(link.nreadable(input), link.nwritable(output)) do
      local pkt = receive(input)
      local payload = pkt.data + o_ethernet_ethertype
      local length = pkt.length
      pkt.length = length + 4
      C.memmove(payload + 4, payload, length - o_ethernet_ethertype)
      cast(uint32_ptr_t, payload)[0] = tag
      transmit(output, pkt)
   end
end

function Untagger:new(conf)
   local o = setmetatable({}, {__index=Untagger})
   o.tag = make_vlan_tag(assert(conf.tag))
   return o
end

function Untagger:push ()
   local input, output = self.input.input, self.output.output
   local tag = self.tag
   for _=1,math.min(link.nreadable(input), link.nwritable(output)) do
      local pkt = receive(input)
      local payload = pkt.data + o_ethernet_ethertype
      if cast(uint32_ptr_t, payload)[0] ~= tag then
         -- Incorrect VLAN tag; drop.
         packet.free(pkt)
      else
         local length = pkt.length
         pkt.length = length - 4
         C.memmove(payload, payload + 4, length - o_ethernet_ethertype - 4)
         transmit(output, pkt)
      end
   end
end
