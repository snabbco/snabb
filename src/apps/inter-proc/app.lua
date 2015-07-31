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

/*   typedef struct {
  //    struct packet *packets[LINK_RING_SIZE];
  //    int head, tail;
      struct link_t *link;
      int64_t txpackets, txbytes, txdrop;
   } transmit_t;

   typedef struct {
      struct link_t *link;
      int64_t rxpackets, rxbytes;
   } receive_t;
*/
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
      txpackets = 0, txbytes = 0, txdrop = 0,
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
   end
end


function Transmit:report()
   print (string.format("Transmit app: %16s packets, %16s bytes",
      lib.comma_value(self.txpackets), lib.comma_value(self.txbytes)))
end



Receive = {}
Receive.__index = Receive


function Receive:new(arg)
   return setmetatable({
      link = shm.map('//'..root..arg.linkname, 'struct link_t'),
      rxpackets = 0, rxbytes = 0,
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
   end
end


function Receive:report()
   print (string.format("Receive app: %16s packets, %16s bytes",
      lib.comma_value(self.rxpackets), lib.comma_value(self.rxbytes)))
end


---------------------
local S = require('syscall')
local config = require('core.config')
local engine = require('core.app')
local basic_apps = require('apps.basic.basic_apps')

function selftest()
   S.unlink(root..'inter_test')
   local c = config.new()
   config.cpu(c, 'proc1')
   config.cpu(c, 'proc2')
   config.app(c, 'source', basic_apps.Source, {size=120, cpu='proc1'})
   config.app(c, 'transmit', Transmit, {linkname='inter_test', cpu='proc1'})
   config.app(c, 'receive', Receive, {linkname='inter_test', cpu='proc2'})
   config.app(c, 'sink', basic_apps.Sink, {cpu='proc2'})
   config.link(c, 'source.output -> transmit.input')
   config.link(c, 'receive.output -> sink.input')
   engine.configure(c)

   engine.main{duration=1, report={showlinks=true, showapps=true}}
end
