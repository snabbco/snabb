module(...,package.seeall)

local ffi = require('ffi')
local band = require("bit").band
local lib = require('core.lib')
local shm = require('core.shm')
local packet = require('core.packet')


ffi.cdef [[
   struct link_t {
      struct packet *packets[LINK_RING_SIZE];
      struct packet *ret_pks[LINK_RING_SIZE];
      int write, read;
   };
]]

local root = 'link/'
local size = ffi.C.LINK_RING_SIZE
local mask = ffi.C.LINK_RING_SIZE-1
local function step(n) return band(n+1, mask) end


Transmit = {}
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
   local n = inlink:nreadable()
   if n > 128 and band(l.read - l.write - 1, mask) >= n then
      local lw = l.write
      local txbytes = 0
      for i = 1, n do
         if l.ret_pks[lw] ~= nil then l.ret_pks[lw]:free() end
         local p = inlink:receive()
         l.packets[lw] = p
         txbytes = txbytes + p.length
         lw = step(lw)
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



Receive = {}
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
   if n > 128 and outlink:nwritable() >= n then
      local lr = l.read
      local rxbytes = 0
      for i = 1, n do
         local p = l.packets[lr]
         rxbytes = rxbytes + p.length
         outlink:transmit(p)
         l.ret_pks[lr] = packet.allocate()
         lr = step(lr)
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


