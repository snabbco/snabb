module(...,package.seeall)

local ffi = require('ffi')
local band = require("bit").band
local lib = require('core.lib')
local shm = require('core.shm')
local packet = require('core.packet')
local link = require('core.link')
require('apps.inter_proc.inter_proc.h')

local pfree = packet.free
local link_receive, link_transmit = link.receive, link.transmit

local root = 'link/'
local size = ffi.C.LINK_RING_SIZE
local mask = ffi.C.LINK_RING_SIZE-1


-- inter-process Receive app
--
-- Receives packet pointers sent from a `Transmit` app on a different process,
-- bound to the same <linkname>.
--
-- Received packets are our responsibility now, must be eventually recycled.
-- To maintain allocation/recycling balance between both processes, for
-- each packet received, an empty packet buffer is sent to the transmitting
-- process.
--
-- No packets are received until the interprocess link is half full (128 packets)
-- and the output link has enough capacity to receive them all.

local Receive = {_NAME = _NAME}
Receive.__index = Receive


function Receive:new(arg)
   return setmetatable({
      link = shm.map('//'..root..arg.linkname, 'struct link_t'),
      rxpackets = 0, rxbytes = 0, rxcycles = 0,
   }, Receive)
end


function Receive:pull()
   local outlink = self.output.output
   local l = self.link
   local n = band(l.write - l.read, mask)
   if n > 128 and link.nwritable(outlink) >= n then
      local lr = l.read
      local rxbytes = 0
      for i = 1, n do
         local p = l.packets[lr]
         rxbytes = rxbytes + p.length
         link_transmit(outlink, p)
         l.ret_pks[lr] = packet.allocate()
         lr = band(lr+1, mask)
      end
      l.read = lr
      self.rxpackets = self.rxpackets + n
      self.rxbytes = self.rxbytes + rxbytes
      self.rxcycles = self.rxcycles + 1
   end
end


function Receive:report()
   print (string.format("Receive app: %16s packets, %16s bytes, %16s cycles (%g packets/cycle)",
      lib.comma_value(self.rxpackets), lib.comma_value(self.rxbytes), lib.comma_value(self.rxcycles),
      tonumber(self.rxpackets) / tonumber(self.rxcycles)))
end


return Receive
