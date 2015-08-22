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
