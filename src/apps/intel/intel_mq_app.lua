module(...,package.seeall)

local app         = require("core.app")
local config      = require("core.config")
local basic_apps  = require("apps.basic.basic_apps")
local link        = require("core.link")
local buffer      = require("core.buffer")
local packet      = require("core.packet")
local lib         = require("core.lib")
local register    = require("lib.hardware.register")
local intel10g_mq = require("apps.intel.intel10g_mq")
local vfio        = require("lib.hardware.vfio")
local multiqueue  = require("lib.hardware.multiqueue")
local intel_sq    = require('apps.intel.intel_app')


Intel82599_mq = {}
Intel82599_mq.__index = Intel82599_mq

-- Create an Intel82599_mq App for the device with 'pciaddress'.
function Intel82599_mq:new (args)
   args = config.parse_app_arg(args)
--    local a = app.new(Intel82599_mq)
   local a = setmetatable({}, Intel82599_mq)
   a.dev = multiqueue.new(intel10g_mq, args.pciaddr):open(args)
   return a
end

-- Pull in packets from the network and queue them on our 'tx' link.
function Intel82599_mq:pull ()
   local l = self.output.tx
   if l == nil then return end
   self.dev:sync_receive()
   while not link.full(l) and self.dev:can_receive() do
      link.transmit(l, self.dev:receive())
   end
   while self.dev:can_add_receive_buffer() do
      self.dev:add_receive_buffer(buffer.allocate())
   end
end

-- Push packets from our 'rx' link onto the network.
function Intel82599_mq:push ()
   local l = self.input.rx
   if l == nil then return end
   while not link.empty(l) and self.dev:can_transmit() do
      local p = link.receive(l)
      self.dev:transmit(p)
      packet.deref(p)
   end
   self.dev:sync_transmit()
end

-- Report on relevant status and statistics.
function Intel82599_mq:report ()
   print("report on intel device", self.dev.pf.pciaddress, self.dev.poolnum)
   --register.dump(self.dev.r)
   register.dump(self.dev.s, true)
   if self.dev.rxstats then
      for name,v in pairs(self.dev:get_rxstats()) do
         io.write(string.format('%30s: %d\n', 'rx '..name, v))
      end
   end
   if self.dev.txstats then
      for name,v in pairs(self.dev:get_txstats()) do
         io.write(string.format('%30s: %d\n', 'tx '..name, v))
      end
   end
   register.dump({
      self.dev.r.TDH, self.dev.r.TDT,
      self.dev.r.RDH, self.dev.r.RDT,
      self.dev.pf.r.LINKS,
   })
--    register.dump(self.dev.r)
--    register.dump(self.dev.pf.r)
--    print ('LINKS', self.dev.r.LINKS, type(self.dev.r.LINKS))
--    io.write(("%40s %s\n"):format(self.dev.r.LINKS, self.dev.r.LINKS.longname))
end


function selftestA()
   local config = require("core.config")

   d1 = lib.hexundump ([[
      52:54:00:65:43:21 52:54:00:12:34:56 08 00 45 00
      00 54 c3 cd 40 00 40 01 f3 23 c0 a8 01 66 c0 a8
      01 01 08 00 57 ea 61 1a 00 06 5c ba 16 53 00 00
      00 00 04 15 09 00 00 00 00 00 10 11 12 13 14 15
      16 17 18 19 1a 1b 1c 1d 1e 1f 20 21 22 23 24 25
      26 27 28 29 2a 2b 2c 2d 2e 2f 30 31 32 33 34 35
      36 37
   ]], 98)                  -- src: d1q0    dst: d2q0
   d2 = lib.hexundump ([[
      52:54:00:78:9A:BC 52:54:00:12:34:56 08 00 45 00
      00 54 c3 cd 40 00 40 01 f3 23 c0 a8 01 66 c0 a8
      01 01 08 00 57 ea 61 1a 00 06 5c ba 16 53 00 00
      00 00 04 15 09 00 00 00 00 00 10 11 12 13 14 15
      16 17 18 19 1a 1b 1c 1d 1e 1f 20 21 22 23 24 25
      26 27 28 29 2a 2b 2c 2d 2e 2f 30 31 32 33 34 35
      36 37
   ]], 98)                 -- src: d1q0    dst: d1q1
   d3 = lib.hexundump ([[
      ff:ff:ff:ff:ff:ff 52:54:00:12:34:56 08 00 45 00
      00 54 c3 cd 40 00 40 01 f3 23 c0 a8 01 66 c0 a8
      01 01 08 00 57 ea 61 1a 00 06 5c ba 16 53 00 00
      00 00 04 15 09 00 00 00 00 00 10 11 12 13 14 15
      16 17 18 19 1a 1b 1c 1d 1e 1f 20 21 22 23 24 25
      26 27 28 29 2a 2b 2c 2d 2e 2f 30 31 32 33 34 35
      36 37
   ]], 98)                 -- src: d1q0    dst: broadcast
--    print ('d:', lib.hexdump(d))

   local c = config.new()
   config.app(c, 'source', basic_apps.Join)
   config.app(c, 'd1q0', Intel82599_mq, [[{
      pciaddr = '0000:05:00.0',
      macaddr='52:54:00:12:34:56',
--       promisc=true,
      rxcounter=1,
      txcounter=2,
--       vlan=2,
   }]])
   config.app(c, 'd1q1', Intel82599_mq, [[{
      pciaddr = '0000:05:00.0',
      macaddr='52:54:00:78:9A:BC',
--       promisc=true,
      rxcounter=3,
      txcounter=4,
--       vlan=2,
   }]])
   config.app(c, 'd1q2', Intel82599_mq, [[{
      pciaddr = '0000:05:00.0',
      macaddr='52:54:00:11:22:33',
      mirror={port='inout', pool=true},
      rxcounter=7,
      txcounter=8,
   }]])
--    config.app(c, 'd2q0', Intel82599_mq, [[{
--       pciaddr = '0000:8a:00.0',
--       macaddr='52:54:00:65:43:21',
-- --       promisc=true,
--       mirror={port=true},
--       rxcounter=5,
--       txcounter=6,
--    }]])
   config.app(c, 'd2', intel_sq.Intel82599, '0000:8a:00.0')
   config.app(c, 'sink', basic_apps.Sink)
   config.link(c, 'source.out -> d1q0.rx')
   config.link(c, 'd1q0.tx -> sink.in1')
   config.link(c, 'd1q1.tx -> sink.in2')
   config.link(c, 'd1q2.tx -> sink.in3')
   config.link(c, 'd2.tx -> sink.in4')
   app.configure(c)
   buffer.preallocate(100000)
   for _ = 1,1000 do
--       local p = packet.from_data(d1)
--       local p = packet.from_data(d2)
      link.transmit(app.app_table.source.output.out, packet.from_data(d1))
      link.transmit(app.app_table.source.output.out, packet.from_data(d2))
--       link.transmit(app.app_table.source.output.out, packet.from_data(d3))
   end
   app.main({duration = 1})
end

function selftest()
   local config = require("core.config")
   d1 = lib.hexundump ([[
      52:54:00:65:43:21 52:54:00:12:34:56 08 00 45 00
      00 54 c3 cd 40 00 40 01 f3 23 c0 a8 01 66 c0 a8
      01 01 08 00 57 ea 61 1a 00 06 5c ba 16 53 00 00
      00 00 04 15 09 00 00 00 00 00 10 11 12 13 14 15
      16 17 18 19 1a 1b 1c 1d 1e 1f 20 21 22 23 24 25
      26 27 28 29 2a 2b 2c 2d 2e 2f 30 31 32 33 34 35
      36 37
   ]], 98)                  -- src: d1    dst: d2q1
   d2 = lib.hexundump ([[
      52:54:00:78:9A:BC 52:54:00:12:34:56 08 00 45 00
      00 54 c3 cd 40 00 40 01 f3 23 c0 a8 01 66 c0 a8
      01 01 08 00 57 ea 61 1a 00 06 5c ba 16 53 00 00
      00 00 04 15 09 00 00 00 00 00 10 11 12 13 14 15
      16 17 18 19 1a 1b 1c 1d 1e 1f 20 21 22 23 24 25
      26 27 28 29 2a 2b 2c 2d 2e 2f 30 31 32 33 34 35
      36 37
   ]], 98)                 -- src: d1    dst: d2q2
   d3 = lib.hexundump ([[
      ff:ff:ff:ff:ff:ff 52:54:00:12:34:56 08 00 45 00
      00 54 c3 cd 40 00 40 01 f3 23 c0 a8 01 66 c0 a8
      01 01 08 00 57 ea 61 1a 00 06 5c ba 16 53 00 00
      00 00 04 15 09 00 00 00 00 00 10 11 12 13 14 15
      16 17 18 19 1a 1b 1c 1d 1e 1f 20 21 22 23 24 25
      26 27 28 29 2a 2b 2c 2d 2e 2f 30 31 32 33 34 35
      36 37
   ]], 98)                 -- src: d1    dst: broadcast
--    print ('d:', lib.hexdump(d))

   local c = config.new()
   config.app(c, 'source', basic_apps.Join)
   config.app(c, 'd1', intel_sq.Intel82599, '0000:8a:00.0')
   config.app(c, 'd2q1', Intel82599_mq, [[{
      pciaddr = '0000:05:00.0',
      macaddr='52:54:00:65:43:21',
--       mirror={port=true},
      rxcounter=1,
      txcounter=2,
   }]])
   config.app(c, 'd2q2', Intel82599_mq, [[{
      pciaddr = '0000:05:00.0',
      macaddr='52:54:00:78:9A:BC',
--       promisc=true,
      rxcounter=3,
      txcounter=4,
--       vlan=2,
   }]])
   config.app(c, 'd2q3', Intel82599_mq, [[{
      pciaddr = '0000:05:00.0',
      macaddr='52:54:00:11:22:33',
      mirror={port='inout'},
      rxcounter=7,
      txcounter=8,
   }]])
   config.app(c, 'sink', basic_apps.Sink)
   config.link(c, 'source.out -> d1.rx')
   config.link(c, 'd2q1.tx -> sink.in1')
   config.link(c, 'd2q2.tx -> sink.in2')
   config.link(c, 'd2q3.tx -> sink.in3')
   app.configure(c)
   buffer.preallocate(100000)
   for _ = 1,1000 do
--       local p = packet.from_data(d1)
--       local p = packet.from_data(d2)
      link.transmit(app.app_table.source.output.out, packet.from_data(d1))
      link.transmit(app.app_table.source.output.out, packet.from_data(d2))
      link.transmit(app.app_table.source.output.out, packet.from_data(d3))
   end
   app.main({duration = 1})
end
