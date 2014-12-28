module(...,package.seeall)

local ffi      = require "ffi"
local C        = ffi.C
local zone = require("jit.zone")
local basic_apps = require("apps.basic.basic_apps")
local lib      = require("core.lib")
local pci      = require("lib.hardware.pci")
local register = require("lib.hardware.register")
local intel10g = require("apps.intel.intel10g")
local freelist = require("core.freelist")
local receive, transmit, full, empty = link.receive, link.transmit, link.full, link.empty
Intel82599 = {}
Intel82599.__index = Intel82599

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
function Intel82599:new (arg)
   local conf = config.parse_app_arg(arg)

   if conf.vmdq then
      if devices[conf.pciaddr] == nil then
         devices[conf.pciaddr] = {pf=intel10g.new_pf(conf.pciaddr):open(), vflist={}}
      end
      local dev = devices[conf.pciaddr]
      local poolnum = firsthole(dev.vflist)-1
      local vf = dev.pf:new_vf(poolnum)
      dev.vflist[poolnum+1] = vf
      return setmetatable({dev=vf:open(conf)}, Intel82599)
   else
      local dev = intel10g.new_sf(conf.pciaddr):open()
      if not dev then return null end
      return setmetatable({dev=dev, zone="intel"}, Intel82599)
   end
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
end


function Intel82599:reconfig(arg)
   local conf = config.parse_app_arg(arg)
   assert((not not self.dev.pf) == (not not conf.vmdq), "Can't reconfig from VMDQ to single-port or viceversa")

   self.dev:reconfig(conf)
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
   for i=1,128 do
      if full(l) or not self.dev:can_receive() then break end
      transmit(l, self.dev:receive())
   end
   self:add_receive_buffers()
end

function Intel82599:add_receive_buffers ()
   -- Generic buffers
   while self.dev:can_add_receive_buffer() do
      self.dev:add_receive_buffer(packet.allocate())
   end
end

-- Push packets from our 'rx' link onto the network.
function Intel82599:push ()
   local l = self.input.rx
   if l == nil then return end
   while not empty(l) and self.dev:can_transmit() do
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

   local pcideva = os.getenv("SNABB_TEST_INTEL10G_PCIDEVA")
   local pcidevb = os.getenv("SNABB_TEST_INTEL10G_PCIDEVB")
   if not pcideva or not pcidevb then
      print("SNABB_TEST_INTEL10G_[PCIDEVA | PCIDEVB] was not set\nTest skipped")
      os.exit(engine.test_skipped_code)
   end

   print ("100 VF initializations:")
   manyreconf(pcideva, pcidevb, 100, false)
   print ("100 PF full cycles")
   manyreconf(pcideva, pcidevb, 100, true)

   ck(pcideva, pcidevb)

   mq_sw(pcideva)
   engine.main({duration = 1, report={showlinks=true, showapps=false}})
   do
      local a0Sends = engine.app_table.nicAm0.input.rx.stats.txpackets
      local a1Gets = engine.app_table.nicAm1.output.tx.stats.rxpackets
      -- Check propertions with some modest margin for error
      if a1Gets < a0Sends * 0.45 or a1Gets > a0Sends * 0.55 then
         print("mq_sw: wrong proportion of packets passed/discarded")
         os.exit(1)
      end
   end

   sq_sq(pcideva, pcidevb)
   engine.main({duration = 1, report={showlinks=true, showapps=false}})

   do
      local aSends = engine.app_table.nicA.input.rx.stats.txpackets
      local aGets = engine.app_table.nicA.output.tx.stats.rxpackets
      local bSends = engine.app_table.nicB.input.rx.stats.txpackets
      local bGets = engine.app_table.nicB.output.tx.stats.rxpackets

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
   engine.main({duration = 1, report={showlinks=true, showapps=false}})

   do
      local aSends = engine.app_table.nicAs.input.rx.stats.txpackets
      local b0Gets = engine.app_table.nicBm0.output.tx.stats.rxpackets
      local b1Gets = engine.app_table.nicBm1.output.tx.stats.rxpackets

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
   config.link(c, 'source_ms.out -> repeater_ms.input')
   config.link(c, 'repeater_ms.output -> nicAs.rx')
   config.link(c, 'nicAs.tx -> sink_ms.in1')
   config.link(c, 'nicBm0.tx -> sink_ms.in2')
   config.link(c, 'nicBm1.tx -> sink_ms.in3')
   engine.configure(c)
   link.transmit(engine.app_table.source_ms.output.out, packet.from_string(d1))
   link.transmit(engine.app_table.source_ms.output.out, packet.from_string(d2))
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
   config.link(c, 'source_ms.out -> repeater_ms.input')
   config.link(c, 'repeater_ms.output -> nicAm0.rx')
   config.link(c, 'nicAm0.tx -> sink_ms.in1')
   config.link(c, 'nicAm1.tx -> sink_ms.in2')
   engine.configure(c)
   link.transmit(engine.app_table.source_ms.output.out, packet.from_string(d1))
   link.transmit(engine.app_table.source_ms.output.out, packet.from_string(d2))
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
      config.link(c, 'source_ms.out -> repeater_ms.input')
      config.link(c, 'repeater_ms.output -> nicAm0.rx')
      config.link(c, 'nicAm0.tx -> sink_ms.in1')
      config.link(c, 'nicAm1.tx -> sink_ms.in2')
      if do_pf then engine.configure(config.new()) end
      engine.configure(c)
      link.transmit(engine.app_table.source_ms.output.out, packet.from_string(d1))
      link.transmit(engine.app_table.source_ms.output.out, packet.from_string(d2))
      engine.main({duration = 0.1, no_report=true})
      cycles = cycles + 1
      redos = redos + engine.app_table.nicAm1.dev.pf.redos
      maxredos = math.max(maxredos, engine.app_table.nicAm1.dev.pf.redos)
      waits = waits + engine.app_table.nicAm1.dev.pf.waitlu_ms
      local sent = engine.app_table.nicAm0.input.rx.stats.txpackets
      io.write (('test #%3d: VMDq VLAN=%d; 100ms burst. packet sent: %s\n'):format(i, 100+i, lib.comma_value(sent-prevsent)))
      if sent == prevsent then
         io.write("error: NIC transmit counter did not increase\n")
         os.exit(2)
      end
   end
   io.write (pcidevA, ": avg wait_lu: ", waits/cycles, ", max redos: ", maxredos, ", avg: ", redos/cycles, '\n')
end


function ck(pcidevA, pcidevB)
   local _num_pkts = 0
   local _num_need_cksum, _num_valid_cksum = '', ''
   local _good_ip_csum, _good_udp_csum = '', ''
   local function get_csum(p, offset)
      local b = p.data
      return b[offset] * 256 + b[offset+1]
   end
   local function clear_csum(p, offset)
      local b = p.data
      b[offset] = 0
      b[offset+1] = 0
   end
   local function verify_pkt(p)
      _num_pkts = _num_pkts + 1
      io.write(string.format('# %d: flags: %02X, ip_chk: %04X, udp_chk: %04X\n',
         _num_pkts, tonumber(p.flags), get_csum(p, 24), get_csum(p, 40)))
      if bit.band(p.flags, C.PACKET_NEEDS_CSUM) ~= 0 then
         _num_need_cksum = _num_need_cksum .. ',' .. _num_pkts
      end
      if bit.band(p.flags, C.PACKET_CSUM_VALID) ~= 0 then
         _num_valid_cksum = _num_valid_cksum .. ',' .. _num_pkts
      end
      if get_csum(p, 24) == 0x7375 then
         _good_ip_csum = _good_ip_csum .. ',' .. _num_pkts
      end
      if get_csum(p, 40) == 0xA590 then
         _good_udp_csum = _good_udp_csum .. ',' .. _num_pkts
      end
   end

   -- IPv4, UDP, all checksums
   local d = lib.hexundump([[
      5254 0002 0202 5254 0001 0101 0800 4500
      0046 f917 4000 4011 7375 c0a8 0166 0808
      0404 9503 0035 0032 A590 a910 0100 0001
      0000 0000 0000 0237 3601 3603 3137 3001
      3833 0769 6e2d 6164 6472 0461 7270 6100
      000c 0001
   ]], 84)
   local p1 = packet.from_string (d)
   local p2 = packet.clone (p1)
   p2.flags = bit.bor(p2.flags, C.PACKET_NEEDS_CSUM)

   -- remove L4 checksum
   local p3 = packet.clone (p1)
   clear_csum(p3, 40)
   local p4 = packet.clone (p3)
   p4.flags = bit.bor(p4.flags, C.PACKET_NEEDS_CSUM)

   -- remove IP checksum
   local p5 = packet.clone (p3)
   clear_csum(p5, 24)
   local p6 = packet.clone (p5)
   p6.flags = bit.bor(p6.flags, C.PACKET_NEEDS_CSUM)

   engine.configure(config.new())
   local c = config.new()
   config.app(c, 'source_ms', basic_apps.Join)
   config.app(c, 'nicAm0', Intel82599, {
   -- first VF on NIC A
      pciaddr = pcidevA,
      vmdq = true,
      macaddr = '52:54:00:01:01:01',
   })
   config.app(c, 'nicAm1', Intel82599, {
   -- second VF on NIC A
      pciaddr = pcidevB,
      vmdq = true,
      macaddr = '52:54:00:02:02:02',
   })
   config.app(c, 'sink_ms', basic_apps.Sink, {callback = verify_pkt})
   config.link(c, 'source_ms.out -> nicAm0.rx')
   config.link(c, 'nicAm0.tx -> sink_ms.in1')
   config.link(c, 'nicAm1.tx -> sink_ms.in2')
   engine.configure(c)
   print ('------')
   print ('send packets with and without asking for checksum, see what happens')
   local src_out = engine.app_table.source_ms.output.out
   link.transmit(src_out, p1)
   link.transmit(src_out, p2)
   link.transmit(src_out, p3)
   link.transmit(src_out, p4)
   link.transmit(src_out, p5)
   link.transmit(src_out, p6)

   engine.main({duration = 1, report={showlinks=true, showapps=false}})
   print (string.format('_num_pkts %s, _num_need_cksum %s, _num_valid_cksum %s',
      _num_pkts, _num_need_cksum, _num_valid_cksum))
   print (string.format('_good_ip_csum %s, _good_udp_csum %s',
      _good_ip_csum, _good_udp_csum))
   if engine.app_table.source_ms.missing then
      os.exit(1)
   end
end
