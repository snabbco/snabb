module(..., package.seeall)

local usage = require("program.snabbmark.README_inc")

local basic_apps = require("apps.basic.basic_apps")
local pci           = require("lib.hardware.pci")
local ethernet      = require("lib.protocol.ethernet")
local freelist      = require("core.freelist")
local ffi = require("ffi")
local C = ffi.C

function run (args)
   local command = table.remove(args, 1)
   if command == 'basic1' and #args == 1 then
      basic1(unpack(args))
   elseif command == 'nfvconfig' and #args == 4 then
      nfvconfig(unpack(args))
   elseif command == 'solarflare' and #args >= 2 and #args <= 3 then
      solarflare(unpack(args))
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
--   config.link(c, "Tee.tx2 -> Sink.rx2")
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
   engine.report_pmu()
   print()
   print(("Processed %.1f million packets in %.2f seconds (rate: %.1f Mpps)."):format(packets / 1e6, runtime, packets / runtime / 1e6))
end

function nfvconfig (pciaddr, confpath_x, confpath_y, nloads)
   local nfvconfig = require("program.snabbnfv.nfvconfig")
   nloads = tonumber(nloads)
      or error("Invalid number of iterations: " .. nloads)

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

function get_sf_devices()
   pci.scan_devices()

   local sf_devices = {}
   for _, device in pairs(pci.devices) do
      if device.usable and device.driver == 'apps.solarflare.solarflare' then
         sf_devices[#sf_devices + 1] = device
      end
   end

   return sf_devices
end

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
      main.exit(43)
   end

   local sf_devices = get_sf_devices()
   if #sf_devices < 2 then
      print([[did not find two Solarflare NICs in system, can't continue]])
      main.exit(43)
   end

   local send_device = sf_devices[1]
   local receive_device = sf_devices[2]

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
