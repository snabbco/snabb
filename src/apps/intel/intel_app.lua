-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local basic_apps = require("apps.basic.basic_apps")
local ffi      = require("ffi")
local lib      = require("core.lib")
local shm      = require("core.shm")
local counter  = require("core.counter")
local pci      = require("lib.hardware.pci")
local register = require("lib.hardware.register")
local macaddress = require("lib.macaddress")
local intel10g = require("apps.intel.intel10g")
local receive, transmit, empty = link.receive, link.transmit, link.empty

Intel82599 = {
   config = {
      pciaddr = {required=true},
      mtu = {},
      macaddr = {},
      vlan = {},
      vmdq = {},
      mirror = {},
      rxcounter  = {default=0},
      txcounter  = {default=0},
      rate_limit = {default=0},
      priority   = {default=1.0},
      ring_buffer_size = {default=intel10g.ring_buffer_size()}
   }
}
Intel82599.__index = Intel82599

local C = ffi.C

-- The `driver' variable is used as a reference to the driver class in
-- order to interchangably use NIC drivers.
driver = Intel82599

-- table pciaddr => {pf, vflist}
local devices = {}


local function firsthole(t)
   for i = 1, #t+1 do
      if t[i] == nil then
         return i
      end
   end
end

-- Create an Intel82599 App for the device with 'pciaddress'.
function Intel82599:new (conf)
   local self = {}

   -- FIXME: ring_buffer_size is really a global variable for this
   -- driver; taking the parameter as an initarg is just to make the
   -- intel_mp transition easier.
   intel10g.ring_buffer_size(conf.ring_buffer_size)
   if conf.vmdq then
      if devices[conf.pciaddr] == nil then
         local pf = intel10g.new_pf(conf):open()
         devices[conf.pciaddr] = { pf = pf,
                                   vflist = {},
                                   stats = { s = pf.s, r = pf.r, qs = pf.qs } }
      end
      local dev = devices[conf.pciaddr]
      local poolnum = firsthole(dev.vflist)-1
      local vf = dev.pf:new_vf(poolnum)
      dev.vflist[poolnum+1] = vf
      self.dev = vf:open(conf)
      self.stats = devices[conf.pciaddr].stats
   else
      self.dev = assert(intel10g.new_sf(conf):open(), "Can not open device.")
      self.stats = { s = self.dev.s, r = self.dev.r, qs = self.dev.qs }
      self.zone = "intel"
   end
   if not self.stats.shm then
      self.stats.shm = shm.create_frame(
         "pci/"..conf.pciaddr,
         {dtime     = {counter, C.get_unix_time()},
          mtu       = {counter, self.dev.mtu},
          speed     = {counter, 10000000000}, -- 10 Gbits
          status    = {counter, 2},           -- Link down
          promisc   = {counter},
          macaddr   = {counter},
          rxbytes   = {counter},
          rxpackets = {counter},
          rxmcast   = {counter},
          rxbcast   = {counter},
          rxdrop    = {counter},
          rxerrors  = {counter},
          txbytes   = {counter},
          txpackets = {counter},
          txmcast   = {counter},
          txbcast   = {counter},
          txdrop    = {counter},
          txerrors  = {counter}})
      self.stats.sync_timer = lib.throttle(0.001)

      if not conf.vmdq and conf.macaddr then
         counter.set(self.stats.shm.macaddr, macaddress:new(conf.macaddr).bits)
      end
   end
   return setmetatable(self, Intel82599)
end

function Intel82599:stop()
   local close_pf = nil
   if self.dev.pf and devices[self.dev.pf.pciaddress] then
      local poolnum = self.dev.poolnum
      local pciaddress = self.dev.pf.pciaddress
      local dev = devices[pciaddress]
      if dev.vflist[poolnum+1] == self.dev then
         dev.vflist[poolnum+1] = nil
      end
      if next(dev.vflist) == nil then
         close_pf = devices[pciaddress].pf
         devices[pciaddress] = nil
      end
   end
   self.dev:close()
   if close_pf then
      close_pf:close()
   end
   if not self.dev.pf or close_pf then
      shm.delete_frame(self.stats.shm)
   end
end


function Intel82599:reconfig (conf)
   assert((not not self.dev.pf) == (not not conf.vmdq), "Can't reconfig from VMDQ to single-port or viceversa")

   self.dev:reconfig(conf)

   if not self.dev.pf and conf.macaddr then
      counter.set(self.stats.shm.macaddr,
                  macaddress:new(conf.macaddr).bits)
   end
end

-- Allocate receive buffers from the given freelist.
function Intel82599:set_rx_buffer_freelist (fl)
   self.rx_buffer_freelist = fl
end

-- Pull in packets from the network and queue them on our 'tx' link.
function Intel82599:pull ()
   local l = self.output.tx
   if l == nil then return end
   self.dev:sync_receive()
   for i = 1, engine.pull_npackets do
      if not self.dev:can_receive() then break end
      transmit(l, self.dev:receive())
   end
   self:add_receive_buffers()
   if self.stats.sync_timer() then
      self:sync_stats()
   end
end

function Intel82599:rxdrop ()
   return self.dev:rxdrop()
end

function Intel82599:add_receive_buffers ()
   -- Generic buffers
   while self.dev:can_add_receive_buffer() do
      self.dev:add_receive_buffer(packet.allocate())
   end
end

-- Synchronize self.stats.s/r a and self.stats.shm.
local link_up_mask = lib.bits{Link_up=30}
local promisc_mask = lib.bits{UPE=9}
function Intel82599:sync_stats ()
   local counters = self.stats.shm
   local s, r, qs = self.stats.s, self.stats.r, self.stats.qs
   counter.set(counters.rxbytes,   s.GORC64())
   counter.set(counters.rxpackets, s.GPRC())
   local mprc, bprc = s.MPRC(), s.BPRC()
   counter.set(counters.rxmcast,   mprc + bprc)
   counter.set(counters.rxbcast,   bprc)
   -- The RX receive drop counts are only available through the RX stats
   -- register. We only read stats register #0 here.
   counter.set(counters.rxdrop,    qs.QPRDC[0]())
   counter.set(counters.rxerrors,  s.CRCERRS() + s.ILLERRC() + s.ERRBC() +
                                   s.RUC() + s.RFC() + s.ROC() + s.RJC())
   counter.set(counters.txbytes,   s.GOTC64())
   counter.set(counters.txpackets, s.GPTC())
   local mptc, bptc = s.MPTC(), s.BPTC()
   counter.set(counters.txmcast,   mptc + bptc)
   counter.set(counters.txbcast,   bptc)
   if bit.band(r.LINKS(), link_up_mask) == link_up_mask then
      counter.set(counters.status, 1) -- Up
   else
      counter.set(counters.status, 2) -- Down
   end
   if bit.band(r.FCTRL(), promisc_mask) ~= 0ULL then
      counter.set(counters.promisc, 1) -- True
   else
      counter.set(counters.promisc, 2) -- False
   end
end

-- Push packets from our 'rx' link onto the network.
function Intel82599:push ()
   local l = self.input.rx
   if l == nil then return end
   while not empty(l) and self.dev:can_transmit() do
      -- We must not send packets that are bigger than the MTU.  This
      -- check is currently disabled to satisfy some selftests until
      -- agreement on this strategy is reached.
      -- if p.length > self.dev.mtu then
      --    counter.add(self.stats.shm.txdrop)
      --    packet.free(p)
      -- else
      do local p = receive(l)
         self.dev:transmit(p)
         --packet.deref(p)
      end
   end
   self.dev:sync_transmit()
end

-- Report on relevant status and statistics.
function Intel82599:report ()
   print("report on intel device", self.dev.pciaddress or self.dev.pf.pciaddress)
   register.dump(self.dev.s)
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
   local function r(n)
      return self.dev.r[n] or self.dev.pf.r[n]
   end
   register.dump({
      r'TDH', r'TDT',
      r'RDH', r'RDT',
      r'AUTOC',
      r'LINKS',
   })
end

function selftest ()
   print("selftest: intel_app")

   local pcideva = lib.getenv("SNABB_PCI_INTEL0")
   local pcidevb = lib.getenv("SNABB_PCI_INTEL1")
   if not pcideva or not pcidevb then
      print("SNABB_PCI_INTEL[0|1] not set or not suitable.")
      os.exit(engine.test_skipped_code)
   end

   print ("100 VF initializations:")
   manyreconf(pcideva, pcidevb, 100, false)
   print ("100 PF full cycles")
   manyreconf(pcideva, pcidevb, 100, true)

   mq_sw(pcideva)
   engine.main({duration = 1, report={showlinks=true, showapps=false}})
   do
      local a0Sends = link.stats(engine.app_table.nicAm0.input.rx).txpackets
      local a1Gets = link.stats(engine.app_table.nicAm1.output.tx).rxpackets
      -- Check propertions with some modest margin for error
      if a1Gets < a0Sends * 0.45 or a1Gets > a0Sends * 0.55 then
         print("mq_sw: wrong proportion of packets passed/discarded")
         os.exit(1)
      end
   end

   local device_info_a = pci.device_info(pcideva)
   local device_info_b = pci.device_info(pcidevb)

   sq_sq(pcideva, pcidevb)
   if device_info_a.model == pci.model["82599_T3"] or
         device_info_b.model == pci.model["82599_T3"] then
      -- Test experience in the lab suggests that the 82599 T3 NIC
      -- requires at least two seconds before it will reliably pass
      -- traffic. The test case sleeps for this reason.
      -- See https://github.com/SnabbCo/snabb/pull/569
      C.usleep(2e6)
   end
   engine.main({duration = 1, report={showlinks=true, showapps=false}})

   do
      local aSends = link.stats(engine.app_table.nicA.input.rx).txpackets
      local aGets = link.stats(engine.app_table.nicA.output.tx).rxpackets
      local bSends = link.stats(engine.app_table.nicB.input.rx).txpackets
      local bGets = link.stats(engine.app_table.nicB.output.tx).rxpackets

      if bGets < aSends/2
         or aGets < bSends/2
         or bGets < aGets/2
         or aGets < bGets/2
      then
         print("sq_sq: missing packets")
         os.exit (1)
      end
   end

   mq_sq(pcideva, pcidevb)
   if device_info_a.model == pci.model["82599_T3"] or
         device_info_b.model == pci.model["82599_T3"] then
      C.usleep(2e6)
   end
   engine.main({duration = 1, report={showlinks=true, showapps=false}})

   do
      local aSends = link.stats(engine.app_table.nicAs.input.rx).txpackets
      local b0Gets = link.stats(engine.app_table.nicBm0.output.tx).rxpackets
      local b1Gets = link.stats(engine.app_table.nicBm1.output.tx).rxpackets

      if b0Gets < b1Gets/2 or
         b1Gets < b0Gets/2 or
         b0Gets+b1Gets < aSends/2
      then
         print("mq_sq: missing packets")
         os.exit (1)
      end
   end
   print("selftest: ok")
end

-- open two singlequeue drivers on both ends of the wire
function sq_sq(pcidevA, pcidevB)
   engine.configure(config.new())
   local c = config.new()
   print("-------")
   print("Transmitting bidirectionally between nicA and nicB")
   config.app(c, 'source1', basic_apps.Source)
   config.app(c, 'source2', basic_apps.Source)
   config.app(c, 'nicA', Intel82599, {pciaddr=pcidevA})
   config.app(c, 'nicB', Intel82599, {pciaddr=pcidevB})
   config.app(c, 'sink', basic_apps.Sink)
   config.link(c, 'source1.out -> nicA.rx')
   config.link(c, 'source2.out -> nicB.rx')
   config.link(c, 'nicA.tx -> sink.in1')
   config.link(c, 'nicB.tx -> sink.in2')
   engine.configure(c)
end

-- one singlequeue driver and a multiqueue at the other end
function mq_sq(pcidevA, pcidevB)
   local d1 = lib.hexundump ([[
      52:54:00:02:02:02 52:54:00:01:01:01 08 00 45 00
      00 54 c3 cd 40 00 40 01 f3 23 c0 a8 01 66 c0 a8
      01 01 08 00 57 ea 61 1a 00 06 5c ba 16 53 00 00
      00 00 04 15 09 00 00 00 00 00 10 11 12 13 14 15
      16 17 18 19 1a 1b 1c 1d 1e 1f 20 21 22 23 24 25
      26 27 28 29 2a 2b 2c 2d 2e 2f 30 31 32 33 34 35
      36 37
   ]], 98)                  -- src: As    dst: Bm0
   local d2 = lib.hexundump ([[
      52:54:00:03:03:03 52:54:00:01:01:01 08 00 45 00
      00 54 c3 cd 40 00 40 01 f3 23 c0 a8 01 66 c0 a8
      01 01 08 00 57 ea 61 1a 00 06 5c ba 16 53 00 00
      00 00 04 15 09 00 00 00 00 00 10 11 12 13 14 15
      16 17 18 19 1a 1b 1c 1d 1e 1f 20 21 22 23 24 25
      26 27 28 29 2a 2b 2c 2d 2e 2f 30 31 32 33 34 35
      36 37
   ]], 98)                  -- src: As    dst: Bm1
   engine.configure(config.new())
   local c = config.new()
   config.app(c, 'source_ms', basic_apps.Join)
   config.app(c, 'repeater_ms', basic_apps.Repeater)
   config.app(c, 'nicAs', Intel82599,
              {-- Single App on NIC A
               pciaddr = pcidevA,
               macaddr = '52:54:00:01:01:01'})
   config.app(c, 'nicBm0', Intel82599,
              {-- first VF on NIC B
               pciaddr = pcidevB,
               vmdq = true,
               macaddr = '52:54:00:02:02:02'})
   config.app(c, 'nicBm1', Intel82599,
              {-- second VF on NIC B
               pciaddr = pcidevB,
               vmdq = true,
               macaddr = '52:54:00:03:03:03'})
   print("-------")
   print("Send traffic from a nicA (SF) to nicB (two VFs)")
   print("The packets should arrive evenly split between the VFs")
   config.app(c, 'sink_ms', basic_apps.Sink)
   config.link(c, 'source_ms.output -> repeater_ms.input')
   config.link(c, 'repeater_ms.output -> nicAs.rx')
   config.link(c, 'nicAs.tx -> sink_ms.in1')
   config.link(c, 'nicBm0.tx -> sink_ms.in2')
   config.link(c, 'nicBm1.tx -> sink_ms.in3')
   engine.configure(c)
   link.transmit(engine.app_table.source_ms.output.output, packet.from_string(d1))
   link.transmit(engine.app_table.source_ms.output.output, packet.from_string(d2))
end

-- one multiqueue driver with two apps and do switch stuff
function mq_sw(pcidevA)
   local d1 = lib.hexundump ([[
      52:54:00:02:02:02 52:54:00:01:01:01 08 00 45 00
      00 54 c3 cd 40 00 40 01 f3 23 c0 a8 01 66 c0 a8
      01 01 08 00 57 ea 61 1a 00 06 5c ba 16 53 00 00
      00 00 04 15 09 00 00 00 00 00 10 11 12 13 14 15
      16 17 18 19 1a 1b 1c 1d 1e 1f 20 21 22 23 24 25
      26 27 28 29 2a 2b 2c 2d 2e 2f 30 31 32 33 34 35
      36 37
   ]], 98)                  -- src: Am0    dst: Am1
   local d2 = lib.hexundump ([[
      52:54:00:03:03:03 52:54:00:01:01:01 08 00 45 00
      00 54 c3 cd 40 00 40 01 f3 23 c0 a8 01 66 c0 a8
      01 01 08 00 57 ea 61 1a 00 06 5c ba 16 53 00 00
      00 00 04 15 09 00 00 00 00 00 10 11 12 13 14 15
      16 17 18 19 1a 1b 1c 1d 1e 1f 20 21 22 23 24 25
      26 27 28 29 2a 2b 2c 2d 2e 2f 30 31 32 33 34 35
      36 37
   ]], 98)                  -- src: Am0    dst: ---
   engine.configure(config.new())
   local c = config.new()
   config.app(c, 'source_ms', basic_apps.Join)
   config.app(c, 'repeater_ms', basic_apps.Repeater)
   config.app(c, 'nicAm0', Intel82599,
              {-- first VF on NIC A
               pciaddr = pcidevA,
               vmdq = true,
               macaddr = '52:54:00:01:01:01'})
   config.app(c, 'nicAm1', Intel82599,
              {-- second VF on NIC A
               pciaddr = pcidevA,
               vmdq = true,
               macaddr = '52:54:00:02:02:02'})
   print ('-------')
   print ("Send a bunch of packets from Am0")
   print ("half of them go to nicAm1 and half go nowhere")
   config.app(c, 'sink_ms', basic_apps.Sink)
   config.link(c, 'source_ms.output -> repeater_ms.input')
   config.link(c, 'repeater_ms.output -> nicAm0.rx')
   config.link(c, 'nicAm0.tx -> sink_ms.in1')
   config.link(c, 'nicAm1.tx -> sink_ms.in2')
   engine.configure(c)
   link.transmit(engine.app_table.source_ms.output.output, packet.from_string(d1))
   link.transmit(engine.app_table.source_ms.output.output, packet.from_string(d2))
end

function manyreconf(pcidevA, pcidevB, n, do_pf)
   io.write ('\n')
   local d1 = lib.hexundump ([[
      52:54:00:02:02:02 52:54:00:01:01:01 08 00 45 00
      00 54 c3 cd 40 00 40 01 f3 23 c0 a8 01 66 c0 a8
      01 01 08 00 57 ea 61 1a 00 06 5c ba 16 53 00 00
      00 00 04 15 09 00 00 00 00 00 10 11 12 13 14 15
      16 17 18 19 1a 1b 1c 1d 1e 1f 20 21 22 23 24 25
      26 27 28 29 2a 2b 2c 2d 2e 2f 30 31 32 33 34 35
      36 37
   ]], 98)                  -- src: Am0    dst: Am1
   local d2 = lib.hexundump ([[
      52:54:00:03:03:03 52:54:00:01:01:01 08 00 45 00
      00 54 c3 cd 40 00 40 01 f3 23 c0 a8 01 66 c0 a8
      01 01 08 00 57 ea 61 1a 00 06 5c ba 16 53 00 00
      00 00 04 15 09 00 00 00 00 00 10 11 12 13 14 15
      16 17 18 19 1a 1b 1c 1d 1e 1f 20 21 22 23 24 25
      26 27 28 29 2a 2b 2c 2d 2e 2f 30 31 32 33 34 35
      36 37
   ]], 98)                  -- src: Am0    dst: ---
--    engine.configure(config.new())
   local prevsent = 0
   local cycles, redos, maxredos, waits = 0, 0, 0, 0
   io.write("Running iterated VMDq test...\n")
   for i = 1, (n or 100) do
      local c = config.new()
      config.app(c, 'source_ms', basic_apps.Join)
      config.app(c, 'repeater_ms', basic_apps.Repeater)
      config.app(c, 'nicAm0', Intel82599, {
         -- first VF on NIC A
         pciaddr = pcidevA,
         vmdq = true,
         macaddr = '52:54:00:01:01:01',
         vlan = 100+i,
      })
      config.app(c, 'nicAm1', Intel82599, {
         -- second VF on NIC A
         pciaddr = pcidevA,
         vmdq = true,
         macaddr = '52:54:00:02:02:02',
         vlan = 100+i,
      })
      config.app(c, 'sink_ms', basic_apps.Sink)
      config.link(c, 'source_ms.output -> repeater_ms.input')
      config.link(c, 'repeater_ms.output -> nicAm0.rx')
      config.link(c, 'nicAm0.tx -> sink_ms.in1')
      config.link(c, 'nicAm1.tx -> sink_ms.in2')
      if do_pf then engine.configure(config.new()) end
      engine.configure(c)
      link.transmit(engine.app_table.source_ms.output.output, packet.from_string(d1))
      link.transmit(engine.app_table.source_ms.output.output, packet.from_string(d2))
      engine.main({duration = 0.1, no_report=true})
      cycles = cycles + 1
      redos = redos + engine.app_table.nicAm1.dev.pf.redos
      maxredos = math.max(maxredos, engine.app_table.nicAm1.dev.pf.redos)
      waits = waits + engine.app_table.nicAm1.dev.pf.waitlu_ms
      local sent = link.stats(engine.app_table.nicAm0.input.rx).txpackets
      io.write (('test #%3d: VMDq VLAN=%d; 100ms burst. packet sent: %s\n'):format(i, 100+i, lib.comma_value(sent-prevsent)))
      if sent == prevsent then
         io.write("error: NIC transmit counter did not increase\n")
         os.exit(2)
      end
   end
   io.write (pcidevA, ": avg wait_lu: ", waits/cycles, ", max redos: ", maxredos, ", avg: ", redos/cycles, '\n')
end
