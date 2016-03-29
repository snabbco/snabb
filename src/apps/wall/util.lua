local link = require("core.link")
local ffi  = require("ffi")
local bit  = require("bit")

local l_receive, l_transmit = link.receive, link.transmit
local l_nreadable, l_nwritable = link.nreadable, link.nwritable

local uint16_ptr_t = ffi.typeof("uint16_t*")
local function rd16(address)
   return ffi.cast(uint16_ptr_t, address)[0]
end

local uint32_ptr_t = ffi.typeof("uint32_t*")
local function rd32(address)
   return ffi.cast(uint16_ptr_t, address)[0]
end

local function ipv6_addr_cmp(a, b)
   for i = 1, 16 do
      local d = b - a
      if d ~= 0 then
         return d
      end
   end
   return 0
end

--
-- Base full-duplex application skeleton which passes packets between two
-- endpoints (south <--> north), applying a callback on each packet seen.
-- Usage:
--
--   local MyApp = setmetatable({}, SouthAndNorth)
--
--   function MyApp:on_southbound_packet (pkt):
--      -- Do something with the packet and return a packet to be
--      -- forwarded to the "south" link (possible the same). Return
--      -- "nil" to discard packets.
--      return pkt
--   end
--
local SouthAndNorth = {}
SouthAndNorth.__index = SouthAndNorth

local function _pass_packets (self, ilink, olink, cb)
   if olink then
      local n = math.min(l_nreadable(ilink), l_nwritable(olink))
      for _ = 1, n do
         local p = cb(self, l_receive(ilink))
         if p then
            l_transmit(olink, p)
         end
      end
   elseif l_nreadable(ilink) > 0 then
      -- No output link: kitchen sink
      for _ = 1, l_nreadable(ilink) do
         cb(self, l_receive(ilink))
      end
   end
end

function SouthAndNorth:push_southbound ()
   if self.input.north then
      _pass_packets(self, self.input.north, self.output.south,
         self.on_southbound_packet or (function (s, p) return p end))
   end
end

function SouthAndNorth:push_northbound ()
   if self.input.south then
      _pass_packets(self, self.input.south, self.output.north,
         self.on_northbound_packet or (function (s, p) return p end))
   end
end

function SouthAndNorth:push ()
   self:push_northbound()
   self:push_southbound()
end


return {
   rd16 = rd16;
   rd32 = rd32;

   ipv6_addr_cmp = ipv6_addr_cmp;

   SouthAndNorth = SouthAndNorth;
}
