module(..., package.seeall)

local usage = require("program.snabbmark.README_inc")

local basic_apps = require("apps.basic.basic_apps")
local pci           = require("lib.hardware.pci")
local ethernet      = require("lib.protocol.ethernet")
local freelist      = require("core.freelist")
local lib = require("core.lib")
local ffi = require("ffi")
local C = ffi.C

function run (args)
   local command = table.remove(args, 1)
   if command == 'basic1' and #args == 1 then
      basic1(unpack(args))
   elseif command == 'nfvconfig' and #args == 3 then
      nfvconfig(unpack(args))
   elseif command == 'solarflare' and #args >= 2 and #args <= 3 then
      solarflare(unpack(args))
   elseif command == 'intel1g' and #args >= 2 and #args <= 3 then
      intel1g(unpack(args))
   elseif command == 'byteops' and #args == 0 then
      byteops()
   else
      print(usage) 
      main.exit(1)
   end
end

function basic1 (npackets)
   npackets = tonumber(npackets) or error("Invalid number of packets: " .. npackets)
   local c = config.new()
   -- Simple topology:
   --               .------.
   -- Source ---> Tee      Sink
   --               `------'
   -- Source generates packets, Tee duplicates them, Sink receives
   -- both duplicates.
   config.app(c, "Source", basic_apps.Source)
   config.app(c, "Tee", basic_apps.Tee)
   config.app(c, "Sink", basic_apps.Sink)
   config.link(c, "Source.tx -> Tee.rx")
   config.link(c, "Tee.tx1 -> Sink.rx1")
   config.link(c, "Tee.tx2 -> Sink.rx2")
   engine.configure(c)
   local start = C.get_monotonic_time()
   timer.activate(timer.new("null", function () end, 1e6, 'repeating'))
   while link.stats(engine.app_table.Source.output.tx).txpackets < npackets do
      engine.main({duration = 0.01, no_report = true})
   end
   local finish = C.get_monotonic_time()
   local runtime = finish - start
   local packets = link.stats(engine.app_table.Source.output.tx).txpackets
   engine.report()
   print()
   print(("Processed %.1f million packets in %.2f seconds (rate: %.1f Mpps)."):format(packets / 1e6, runtime, packets / runtime / 1e6))
end

function nfvconfig (confpath_x, confpath_y, nloads)
   local nfvconfig = require("program.snabbnfv.nfvconfig")
   nloads = tonumber(nloads)
      or error("Invalid number of iterations: " .. nloads)

   local pciaddr = lib.getenv("SNABB_PCI0")
   if not pciaddr then
      print("SNABB_PCI0 not set.")
      os.exit(engine.test_skipped_code)
   end

   local load_times, apply_times = {}, {}

   for i=1, nloads do
      -- Load and apply confpath_x.
      engine.configure(nfvconfig.load(confpath_x, pciaddr, "/dev/null"))

      -- Measure loading y.
      local start_load = C.get_monotonic_time()
      local c = nfvconfig.load(confpath_y, pciaddr, "/dev/null")
      local end_load = C.get_monotonic_time()

      -- Measure apply x -> y.
      local start_apply = C.get_monotonic_time()
      engine.configure(c)
      local end_apply = C.get_monotonic_time()

      -- Push results.
      table.insert(load_times, end_load - start_load)
      table.insert(apply_times, end_apply - start_apply)
   end

   engine.report()
   print()

   -- Print results.
   local load_mean, load_max = sumf(unpack(load_times))/#load_times, math.max(unpack(load_times))
   print("load_mean:", ("%.4fs"):format(load_mean))
   print("load_max:", ("%.4fs"):format(load_max))

   local apply_mean, apply_max = sumf(unpack(apply_times))/#apply_times, math.max(unpack(apply_times))
   print("apply_mean:", ("%.4fs"):format(apply_mean))
   print("apply_max:", ("%.4fs"):format(apply_max))

   -- Overall score is load_mean+apply_mean per second.
   print("score: ", ("%.2f"):format(1/(apply_mean + load_mean)))
end

function sumf(a, ...) return a and a + sumf(...) or 0 end

Source = {}

function Source:new(size)
   return setmetatable({}, {__index=Source})
end

function Source:pull()
   for _, o in ipairs(self.output) do
      for i = 1, link.nwritable(o) do
         local p = packet.allocate()
         ffi.copy(p.data, self.to_mac_address, 6)
         ffi.copy(p.data + 6, self.from_mac_address, 6)
         p.length = self.size
         link.transmit(o, p)
      end
   end
end

function Source:set_packet_addresses(from_mac_address, to_mac_address)
   self.from_mac_address, self.to_mac_address = from_mac_address, to_mac_address
   print(string.format("Sending from %02x:%02x:%02x:%02x:%02x:%02x to %02x:%02x:%02x:%02x:%02x:%02x",
                       self.from_mac_address[0],
                       self.from_mac_address[1],
                       self.from_mac_address[2],
                       self.from_mac_address[3],
                       self.from_mac_address[4],
                       self.from_mac_address[5],
                       self.to_mac_address[0],
                       self.to_mac_address[1],
                       self.to_mac_address[2],
                       self.to_mac_address[3],
                       self.to_mac_address[4],
                       self.to_mac_address[5]))
end

function Source:set_packet_size(size)
   self.size = size
end

function solarflare (npackets, packet_size, timeout)
   npackets = tonumber(npackets) or error("Invalid number of packets: " .. npackets)
   packet_size = tonumber(packet_size) or error("Invalid packet size: " .. packet_size)
   if timeout then
      timeout = tonumber(timeout) or error("Invalid timeout: " .. timeout)
   end

   local function load_driver ()
      return require("apps.solarflare.solarflare").SolarFlareNic
   end

   local status, SolarFlareNic = pcall(load_driver)
   if not status then
      print(SolarFlareNic)
      os.exit(engine.test_skipped_code)
   end

   local pciaddr0 = lib.getenv("SNABB_PCI_SOLARFLARE0") or lib.getenv("SNABB_PCI0")
   local pciaddr1 = lib.getenv("SNABB_PCI_SOLARFLARE1") or lib.getenv("SNABB_PCI1")
   local send_device = pciaddr0 and pci.device_info(pciaddr0)
   local receive_device = pciaddr1 and pci.device_info(pciaddr1)
   if not send_device
      or send_device.driver ~= 'apps.solarflare.solarflare'
      or not receive_device
      or receive_device.driver ~= 'apps.solarflare.solarflare'
   then
      print("SNABB_PCI_SOLARFLARE[0|1]/SNABB_PCI[0|1] not set or not suitable.")
      os.exit(engine.test_skipped_code)
   end

   print(string.format("Sending through %s (%s), receiving through %s (%s)",
                       send_device.interface, send_device.pciaddress,
                       receive_device.interface, receive_device.pciaddress))

   local c = config.new()

   -- Topology:
   -- Source -> Solarflare NIC#1 => Solarflare NIC#2 -> Sink

   config.app(c, "source", Source)
   config.app(c, send_device.interface, SolarFlareNic, {ifname=send_device.interface, mac_address = ethernet:pton("02:00:00:00:00:01")})
   config.app(c, receive_device.interface, SolarFlareNic, {ifname=receive_device.interface, mac_address = ethernet:pton("02:00:00:00:00:02")})
   config.app(c, "sink", basic_apps.Sink)

   config.link(c, "source.tx -> " .. send_device.interface .. ".rx")
   config.link(c, receive_device.interface .. ".tx -> sink.rx")

   engine.configure(c)

   engine.app_table.source:set_packet_addresses(engine.app_table[send_device.interface].mac_address,
                                                engine.app_table[receive_device.interface].mac_address)
   engine.app_table.source:set_packet_size(packet_size)

   engine.Hz = false

   local start = C.get_monotonic_time()
   timer.activate(timer.new("null", function () end, 1e6, 'repeating'))
   local n = 0
   local n_max
   if timeout then
      n_max = timeout * 100
   end
   while link.stats(engine.app_table.source.output.tx).txpackets < npackets
      and (not timeout or n < n_max)
   do
      engine.main({duration = 0.01, no_report = true})
      n = n + 1
   end
   local finish = C.get_monotonic_time()
   local runtime = finish - start
   local packets = link.stats(engine.app_table.source.output.tx).txpackets
   engine.report()
   engine.app_table[send_device.interface]:report()
   engine.app_table[receive_device.interface]:report()
   print()
   print(("Processed %.1f million packets in %.2f seconds (rate: %.1f Mpps, %.2f Gbit/s)."):format(packets / 1e6,
                                                                                                   runtime, packets / runtime / 1e6,
                                                                                                   ((packets * packet_size * 8) / runtime) / (1024*1024*1024)))
   if link.stats(engine.app_table.source.output.tx).txpackets < npackets then
      print("Packets lost. Test failed!")
      main.exit(1)
   end
end

-- ---


function intel1g (npackets, packet_size, timeout)
   npackets = tonumber(npackets) or error("Invalid number of packets: " .. npackets)
   packet_size = tonumber(packet_size) or error("Invalid packet size: " .. packet_size)
   if timeout then
      timeout = tonumber(timeout) or error("Invalid timeout: " .. timeout)
   end

   local function load_driver ()
      return require("apps.intel.intel1g").Intel1g
   end

   local status, Intel1gNic = pcall(load_driver)
   if not status then
      print(Intel1gNic)
      os.exit(engine.test_skipped_code)
   end

   local pciaddr0 = lib.getenv("SNABB_PCI0")
   local pciaddr1 = lib.getenv("SNABB_PCI1")
   local send_device = pciaddr0 and pci.device_info(pciaddr0)
   local receive_device = pciaddr1 and pci.device_info(pciaddr1)
print("send_device= ", send_device, "  receive_device= ", receive_device)
   if not send_device
      or send_device.driver ~= 'apps.intel.intel1g'
      or not receive_device
      or receive_device.driver ~= 'apps.intel.intel1g'
   then
      print("SNABB_PCI[0|1] not set, or not suitable Intel i210/i350 NIC.")
      os.exit(engine.test_skipped_code)
   end

send_device.interface= "tx1GE"
receive_device.interface= "rx1GE"

   print(string.format("Sending through %s (%s), receiving through %s (%s)",
                       send_device.interface, send_device.pciaddress,
                       receive_device.interface, receive_device.pciaddress))

   local c = config.new()

   -- Topology:
   -- Source -> Intel1g NIC#1 => Intel1g NIC#2 -> Sink

   config.app(c, "source", Source)
   --config.app(c, send_device.interface, Intel1gNic, {ifname=send_device.interface, mac_address = ethernet:pton("02:00:00:00:00:01")})
   --config.app(c, receive_device.interface, Intel1gNic, {ifname=receive_device.interface, mac_address = ethernet:pton("02:00:00:00:00:02")})
   config.app(c, send_device.interface, Intel1gNic, {pciaddr=pciaddr0})
   config.app(c, receive_device.interface, Intel1gNic, {pciaddr=pciaddr1, rxburst=512})
   config.app(c, "sink", basic_apps.Sink)

   config.link(c, "source.tx -> " .. send_device.interface .. ".rx")
   config.link(c, receive_device.interface .. ".tx -> sink.rx")

   engine.configure(c)

   --engine.app_table.source:set_packet_addresses(engine.app_table[send_device.interface].mac_address,
   --                                             engine.app_table[receive_device.interface].mac_address)
   engine.app_table.source:set_packet_addresses(ethernet:pton("02:00:00:00:00:01"),
                                                ethernet:pton("02:00:00:00:00:02"))
   engine.app_table.source:set_packet_size(packet_size)

   engine.Hz = false

   local start = C.get_monotonic_time()
   timer.activate(timer.new("null", function () end, 1e6, 'repeating'))
   local n = 0
   local n_max
   if timeout then
      n_max = timeout * 100
   end
   while link.stats(engine.app_table.source.output.tx).txpackets < npackets
      and (not timeout or n < n_max)
   do
      engine.main({duration = 0.01, no_report = true})
      n = n + 1
   end
   local finish = C.get_monotonic_time()
   local runtime = finish - start
   local txpackets = link.stats(engine.app_table.source.output.tx).txpackets
   local rxpackets = link.stats(engine.app_table.sink.input.rx).rxpackets
   engine.report()
   engine.app_table[send_device.interface]:report()
   engine.app_table[receive_device.interface]:report()
   print()
   print(("Processed %.1f million packets in %.2f seconds (rate: %.1f Mpps, %.2f Gbit/s, %.2f %% packet loss)."):format(
    txpackets / 1e6, runtime, 
    txpackets / runtime / 1e6,
    ((txpackets * packet_size * 8) / runtime) / (1024*1024*1024),
    (txpackets - rxpackets) *100 / txpackets
   ))
   if link.stats(engine.app_table.source.output.tx).txpackets < npackets then
      print("Packets lost. Test failed!")
      main.exit(1)
   end
end

-- Byteops benchmark

function byteops ()
   print("byteops benchmark:")
   local pmu = require("lib.pmu")
   local cpu = io.open('/proc/cpuinfo'):read('*a'):match("(E5[^\n]*) @")
   print(require("lib.pmu_x86").cpu_model)
   local rowfmt = "@@ %-10s;%-10s;%-10s;%-10s;%-10s;%-10s;%-10s;%-10s;%-10s;%-10s;%-10s;%-10s;%-10s;%-10s;%-10s;%-10s;%-10s;%-10s"
   print(rowfmt:format("cpu", "name", "nbatch", "nbytes", "disp", "lendist", "lenalign", "dstalign", "srcalign",
                       "nanos", "cycle", "refcycle", "instr", "l1-hit", "l2-hit", "l3-hit", "l3-miss", "br-miss"))
   local function row (name, nbatch, nbytes, disp, lendist, lenalign, dstalign, srcalign, nanos, cycle, refcycle, instr, l1h, l2h, l3h, l3m, brm)
      print(rowfmt:format(cpu, name, tostring(nbatch), tostring(nbytes), tostring(disp), tostring(lendist), tostring(lenalign), tostring(dstalign), tostring(srcalign), tostring(nanos), tostring(cycle), tostring(refcycle), tostring(instr), tostring(l1h), tostring(l2h), tostring(l3h), tostring(l3m), tostring(brm)))
   end
   local nbatch = 10000
   local batch = ffi.new("struct { char *src, *dst; uint32_t len; }[?]", nbatch)
   local nbuffer = 10*1024*1024
   local src = ffi.new("char[?]", nbuffer)
   local dst = ffi.new("char[?]", nbuffer)
   local tmp = ffi.new("char[?]", nbuffer)
   local functions = { memcpy = ffi.C.memcpy }

   local function flushcache ()
      ffi.copy(tmp, src, nbuffer)
   end

   -- Set of alignments for src / dst / len values.
   local alignments = {1,2,4,8,16,32,48,64}
   -- Distributions of data sizes (probability density functions).
   -- Test with constant sizes, with uniform sizes, and with
   -- loguniform sizes (proportionally more smaller sizes).
   local sizedist = {'k=64', 'k=256', 'k=1500', 'k=10240', 'uniform', 'loguniform'}
   -- Displacements in memory: fixed location, within L1 cache, within
   -- L2 cache, within L3 cache, main memory.
   local displacement  = {0, 12*1024, 384*1024, 2*1024*1024, nbuffer-10240}

   require("lib.checksum")
   local functions = {memcpy = function (dst, src, len) ffi.C.memcpy(dst, src, len) end,
                      cksum     = function (dst, src, len)  ffi.C.cksum_generic(src, len, 0) end,
--                      cksumsse2 = function (dst, src, len) ffi.C.cksum_sse2(src, len, 0) end,
                      cksumavx2 = function (dst, src, len) ffi.C.cksum_avx2(src, len, 0) end}

   local function align (n, a)
      return n - (n%a)
   end

   local function pick (d)
      if d == 'k=64' then return 64 end
      if d == 'k=256' then return 256 end
      if d == 'k=1500' then return 1500 end
      if d == 'uniform' then return math.random(0, 10240) end
      if d == 'loguniform' then return math.floor(math.exp(math.log(10240)*math.random())) end
      return 0
   end

   for _, srcalign in ipairs(alignments) do
      for _, dstalign in ipairs(alignments) do
         for _, lenalign in ipairs(alignments) do
            for _, lendist in ipairs(sizedist) do
               for _, displacement in ipairs(displacement) do
                  for fname, func in pairs(functions) do
                     local nbytes = 0
                     for i = 0, nbatch-1 do
                        batch[i].src = src + align(math.random(displacement), srcalign)
                        batch[i].dst = dst + align(math.random(displacement), dstalign)
                        batch[i].len = align(pick(lendist), lenalign)
                        nbytes = nbytes + batch[i].len
                     end
                     local function run ()
                        for i = 0, nbatch-1 do
                           local spec = batch[i]
                           func(batch[i].dst, batch[i].src, batch[i].len)
                        end
                     end
                     -- XXX not available on all processors?
                     local events = {'mem_load_uops_retired.l1_hit',
                                     'mem_load_uops_retired.l2_hit',
                                     'mem_load_uops_retired.l3_hit',
                                     'mem_load_uops_retired.l3_miss',
                                     'br_misp_retired.all_branches'}
                     local start = ffi.C.get_time_ns()
                     local _, profile = pmu.measure(run, events)
                     local finish = ffi.C.get_time_ns()
--                     for k,v in pairs(profile) do print(k,v) end
                     row(fname, nbatch, nbytes, displacement, lendist, lenalign, dstalign, srcalign,
                         tonumber(finish-start), profile.cycles, profile.ref_cycles, profile.instructions,
                         profile[events[1]], profile[events[2]], profile[events[3]], profile[events[4]], profile[events[5]])
                  end
               end
            end
         end
      end
   end
   print("byteops: ok")
end

