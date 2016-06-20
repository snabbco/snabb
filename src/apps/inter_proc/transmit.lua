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


-- inter-process Transmit app
--
-- Sends packet pointers to a `Receive` app on a different process,
-- bound to the same <linkname>.  Packet pointers should be valid on
-- both processes if allocated on the DMA-friendly pool managed by
-- core.memory
--
-- Each interprocess link is a shared memory struct (allocated with
-- core.shm) with two synchronized rings: .packets[] holds packet pointers,
-- and .ret_pks[] with "payback" empty packet pointers.
--
-- Packet ownership is transferred too, once transferred, we're not
-- responsible to deallocate a packet. To avoid freelist starvation, the
-- .ret_pks ring can contain "payback" packets that we can recycle into
-- the local freelist.
--
-- To reduce cache trashing, this app only transmits when the `input` link
-- contains at least 128 packets (half capacity) and the interprocess link
-- has enough free space for all available packets.


local Transmit = {_NAME = _NAME}
Transmit.__index = Transmit


function Transmit:new(arg)
   return setmetatable({
      link = shm.map('//'..root..arg.linkname, 'struct link_t'),
      txpackets = 0, txbytes = 0, txdrop = 0, txcycles = 0,
   }, Transmit)
end


function Transmit:push()
   local inlink = self.input.input
   local l = self.link
   local n = link.nreadable(inlink)
   if n > 128 and band(l.read - l.write - 1, mask) >= n then
      local lw = l.write
      local txbytes = 0
      for i = 1, n do
         if l.ret_pks[lw] ~= nil then pfree(l.ret_pks[lw]) end
         local p = link_receive(inlink)
         l.packets[lw] = p
         txbytes = txbytes + p.length
         lw = band(lw+1, mask)
      end
      l.write = lw
      self.txpackets = self.txpackets + n
      self.txbytes = self.txbytes + txbytes
      self.txcycles = self.txcycles + 1
   end
end


function Transmit:report()
   print (string.format("Transmit app: %16s packets, %16s bytes in %16s cycles (%g packets/cycle)",
      lib.comma_value(self.txpackets), lib.comma_value(self.txbytes), lib.comma_value(self.txcycles),
      (tonumber(self.txpackets) / tonumber(self.txcycles))))
end


return Transmit
