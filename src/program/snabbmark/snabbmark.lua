-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local basic_apps = require("apps.basic.basic_apps")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ffi = require("ffi")
local ipv4 = require("lib.protocol.ipv4")
local lib = require("core.lib")
local pci = require("lib.hardware.pci")
local udp = require("lib.protocol.udp")
local usage = require("program.snabbmark.README_inc")

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
   elseif command == 'intel10g' and #args >= 2 and #args <= 3 then
      intel10g(unpack(args))
   elseif command == 'rawsocket' and #args ~= 3 then
      rawsocket(unpack(args))
   elseif command == 'esp' and #args >= 2 then
      esp(unpack(args))
   elseif command == 'hash' and #args <= 1 then
      hash(unpack(args))
   elseif command == 'ctable' and #args == 0 then
      ctable(unpack(args))
   else
      print(usage) 
      main.exit(1)
   end
end

function gbits (bps)
   return (bps * 8) / (1024^3)
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

function Source:new (size)
   size = size or 64
   local p = packet.allocate()
   p.length = size
   return setmetatable({packet=p}, {__index=Source})
end

function Source:pull ()
   for _, o in ipairs(self.output) do
      for i = 1, engine.pull_npackets do
         link.transmit(o, packet.clone(self.packet))
      end
   end
end

function Source:set_packet_addresses (src_mac, dst_mac)
   local p = self.packet
   ffi.copy(p.data, dst_mac, 6)
   ffi.copy(p.data + 6, src_mac, 6)
end

function Source:set_packet_size (size)
   self.packet.length = size
end

function Source:set_packet (packet)
   self.packet = packet
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

   local src_mac = engine.app_table[send_device.interface].mac_address
   local dst_mac = engine.app_table[receive_device.interface].mac_address
   engine.app_table.source:set_packet_addresses(src_mac, dst_mac)
   engine.app_table.source:set_packet_size(packet_size)

   print(("Sending from %s to %s"):format(ethernet:ntop(src_mac),
                                          ethernet:ntop(dst_mac)))

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
                                                                                                   gbits(packets * packet_size / runtime)))
   if link.stats(engine.app_table.source.output.tx).txpackets < npackets then
      print("Packets lost. Test failed!")
      main.exit(1)
   end
end

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

   config.link(c, "source.tx -> " .. send_device.interface .. ".input")
   config.link(c, receive_device.interface .. ".output -> sink.rx")

   engine.configure(c)

   local src_mac, dst_mac = "02:00:00:00:00:01", "02:00:00:00:00:02"
   engine.app_table.source:set_packet_addresses(ethernet:pton(src_mac),
                                                ethernet:pton(dst_mac))
   engine.app_table.source:set_packet_size(packet_size)

   print(("Sending from %s to %s"):format(src_mac, dst_mac))

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

local function get_macaddr (iface)
   local fd = io.open("/sys/class/net/"..iface.."/address", "rt")
   if not fd then return nil end
   local ret = fd:read("*all")
   ret = ret:match("[%x:]+")
   fd:close()
   return ret
end

local function w (...) io.stdout:write(...) end

local function skip (...)
   w(...) w("\n")
   main.exit(engine.test_skipped_code)
end

local function stats (txpackets, rxpackets, runtime, packet_size)
   local total = txpackets / 1e6
   local mpps = txpackets / runtime / 1e6
   local gbps = ((txpackets * packet_size * 8) / runtime) / (1024*1024*1024)
   local loss = (txpackets - rxpackets) * 100 / txpackets
   print()
   print(("Processed %.1f million packets in %.2f seconds (rate: %.1f Mpps, "..
          "%.2f Gbit/s, %.2f %% packet loss)."):format(total, runtime, mpps,
                                                       gbps, loss))
end

local function build_packet (args)
   local ETHER_PROTO_IPV4 = 0x0800
   local PROTO_UDP = 0x11

   local size = args.size or 64
   local src_mac = args.src_mac or "00:00:5E:00:00:01"
   local dst_mac = args.dst_mac or "00:00:5E:00:00:02"

   local dgram = datagram:new()

   local eth_h = ethernet:new({dst = ethernet:pton(dst_mac),
                               src = ethernet:pton(src_mac),
                               type = ETHER_PROTO_IPV4})
   local ip_h = ipv4:new({dst = ipv4:pton("192.0.2.254"),
                          src = ipv4:pton("192.0.2.1"),
                          protocol = PROTO_UDP,
                          ttl = 64})
   local udp_h = udp:new({src_port = math.random(65535),
                          dst_port = math.random(65535)})

   local total_length = size - 14
   local length = total_length - 20

   ip_h:total_length(total_length)
   udp_h:length(length)

   ip_h:checksum()

   local payload_length = length - 8
   local payload = ffi.new("uint8_t[?]", payload_length)
   local count = 0
   for i=0,payload_length-1 do
      payload[i] = count
      count = count + 1
   end

   dgram:push_raw(payload, payload_length)
   dgram:push(udp_h)
   dgram:push(ip_h)
   dgram:push(eth_h)

   return dgram:packet()
end

function intel10g (npackets, packet_size, timeout)
   local function load_driver ()
      return require("apps.intel_mp.intel_mp").Intel
   end
   local function device_info (pciaddr)
      pciaddr = assert(tostring(pciaddr), "Invalid pciaddr: "..pciaddr)
      local device = pciaddr and pci.device_info(pciaddr)
      if not (device or device.driver == 'apps.intel_mp.intel_mp') then
         skip("SNABB_PCI[0|1] not set, or not suitable Intel 10G.")
      end
      return device
   end

   local pciaddr0 = lib.getenv("SNABB_PCI0")
   if not pciaddr0 then
      skip("SNABB_PCI0 not set")
   end
   local pciaddr1 = lib.getenv("SNABB_PCI1")
   if not pciaddr1 then
      skip("SNABB_PCI1 not set")
   end
   local status, Intel10gNic = pcall(load_driver)
   if not status then
      skip("Could not find driver: "..Intel10gNic)
   end

   npackets = tonumber(npackets) or error("Invalid number of packets: " .. npackets)
   packet_size = tonumber(packet_size) or error("Invalid packet size: " .. packet_size)
   timeout = tonumber(timeout) or 1000

   local nic0 = device_info(pciaddr0)
   local nic1 = device_info(pciaddr1)

   nic0.interface = "nic0"
   nic1.interface = "nic1"

   w(("Sending through %s (%s); "):format(nic0.interface, nic0.pciaddress))
   w(("Receiving through %s (%s)"):format(nic1.interface, nic1.pciaddress))
   print("")

   -- Topology:
   -- Source -> Intel10g NIC#1 => Intel10g NIC#2 -> Sink

   -- Initialize apps.
   local c = config.new()
   config.app(c, "source", Source)
   config.app(c, "tee", basic_apps.Tee)
   config.app(c, "sink", basic_apps.Sink)
   config.app(c, nic0.interface, Intel10gNic, {
      pciaddr = pciaddr0,
   })
   config.app(c, nic1.interface, Intel10gNic, {
      pciaddr = pciaddr1,
   })
   config.app(c, "sink", basic_apps.Sink)

   -- Set links.
   config.link(c, "source.tx -> tee.rx")
   config.link(c, "tee.tx -> "..nic0.interface.."."..nic0.rx)
   config.link(c, nic1.interface.."."..nic1.tx.." -> sink.rx")

   -- Set engine.
   engine.configure(c)
   engine.Hz = false

   -- Adjust packet.
   local pkt = build_packet({size = packet_size})
   engine.app_table.source:set_packet(pkt)

   local start = C.get_monotonic_time()
   local txpackets = 0
   local n, n_max = 0, timeout and timeout * 100
   while txpackets < npackets and n < n_max do
      engine.main({duration = 0.01, no_report = true})
      txpackets = link.stats(engine.app_table[nic0.interface].input[nic0.rx]).rxpackets
      n = n + 1
   end
   local rxpackets = link.stats(engine.app_table.sink.input.rx).rxpackets
   local finish = C.get_monotonic_time()
   local runtime = finish - start
   if rxpackets >= txpackets then
      rxpackets = txpackets
   end

   engine.report()

   -- Print stats.
   stats(txpackets, rxpackets, runtime, packet_size)

   if txpackets < npackets then
      print("Packets lost. Test failed!")
      main.exit(1)
   end
end

function rawsocket (npackets, packet_size, timeout)
   local driver = require("apps.socket.raw").RawSocket
   npackets = tonumber(npackets) or 10e3
   packet_size = tonumber(packet_size) or 64
   timeout = tonumber(timeout) or 1000

   local ifname0 = lib.getenv("SNABB_IFNAME0") or lib.getenv("SNABB_PCI0")
   if not ifname0 then
      skip("SNABB_IFNAME0 not set.")
   end
   local ifname1 = lib.getenv("SNABB_IFNAME1") or lib.getenv("SNABB_PCI1")
   if not ifname1 then
      skip("SNABB_IFNAME1 not set.")
   end

   -- Topology:
   -- Source -> Socket NIC#1 => Socket NIC#2 -> Sink

   -- Initialize apps.
   local c = config.new()

   config.app(c, "source", Source)
   config.app(c, "tee", basic_apps.Tee)
   config.app(c, ifname0, driver, ifname0)
   config.app(c, ifname1, driver, ifname1)
   config.app(c, "sink", basic_apps.Sink)

   -- Set links.
   config.link(c, "source.tx -> tee.rx")
   config.link(c, "tee.tx -> "..ifname0..".rx")
   config.link(c, ifname1..".tx -> sink.input")

   -- Set engine.
   engine.configure(c)
   engine.Hz = false

   -- Adjust packet.
   local src_mac = get_macaddr(ifname0) or "00:00:5E:00:00:01"
   local dst_mac = get_macaddr(ifname1) or "00:00:5E:00:00:02"
   local pkt = build_packet({src_mac = src_mac,
                             dst_mac = dst_mac,
                             size = packet_size})
   engine.app_table.source:set_packet(pkt)

   -- Print info.
   w(("Packets: %d; "):format(npackets))
   w(("Packet Size: %d; "):format(packet_size))
   w(("Timeout: %d"):format(timeout))
   print("")

   w(("Sending through %s (%s); "):format(ifname0, src_mac))
   w(("Receiving through %s (%s)"):format(ifname1, dst_mac))
   print("")

   -- Run.
   local start = C.get_monotonic_time()
   timer.activate(timer.new("null", function () end, 1e6, 'repeating'))
   local txpackets = 0
   local n, n_max = 0, timeout and timeout * 100
   while txpackets < npackets and n < n_max do
      txpackets = link.stats(engine.app_table.source.output.tx).txpackets
      engine.main({duration = 0.01, no_report = true})
      n = n + 1
   end
   local finish = C.get_monotonic_time()
   local runtime = finish - start
   local rxpackets = link.stats(engine.app_table.sink.input.input).rxpackets
   if rxpackets >= txpackets then
      rxpackets = txpackets
   end

   -- Print report if any.
   engine.report()

   -- Print stats.
   stats(txpackets, rxpackets, runtime, packet_size)

   if txpackets < npackets then
      print(("Packets lost. Rx: %d. Lost: %d"):format(txpackets, npackets - txpackets))
      main.exit(1)
   end
end


function esp (npackets, packet_size, mode, direction)
   local esp = require("lib.ipsec.esp")
   local ethernet = require("lib.protocol.ethernet")
   local ipv6 = require("lib.protocol.ipv6")
   local datagram = require("lib.protocol.datagram")

   npackets = assert(tonumber(npackets), "Invalid number of packets: " .. npackets)
   packet_size = assert(tonumber(packet_size), "Invalid packet size: " .. packet_size)
   local payload_size = packet_size - ethernet:sizeof() - ipv6:sizeof()
   local payload = ffi.new("uint8_t[?]", payload_size)
   local d = datagram:new(packet.allocate())
   local ip = ipv6:new({})
   ip:payload_length(payload_size)
   d:payload(payload, payload_size)
   d:push(ip)
   if not mode == "tunnel" then
      local eth = ethernet:new({type=0x86dd})
      d:push(eth)
   end
   local plain = d:packet()
   local conf = { spi = 0x0,
                  mode = "aes-gcm-128-12",
                  key = "00112233445566778899AABBCCDDEEFF",
                  salt = "00112233"}
   local enc, dec = esp.encrypt:new(conf), esp.decrypt:new(conf)
   local encap, decap
   if mode == "tunnel" then
      encap = function (p) return enc:encapsulate_tunnel(p, 41) end
      decap = function (p) return dec:decapsulate_tunnel(p) end
   else
      encap = function (p) return enc:encapsulate_transport6(p) end
      decap = function (p) return dec:decapsulate_transport6(p) end
   end
   if direction == "encapsulate" then
      local start = C.get_monotonic_time()
      for i = 1, npackets do
         packet.free(encap(packet.clone(plain)))
      end
      local finish = C.get_monotonic_time()
      local bps = (packet_size * npackets) / (finish - start)
      print(("Encapsulation (packet size = %d): %.2f Gbit/s")
            :format(packet_size, gbits(bps)))
   else
      local encapsulated = encap(packet.clone(plain))
      local start = C.get_monotonic_time()
      for i = 1, npackets do
         packet.free(decap(packet.clone(encapsulated)))
         dec.seq.no = 0
         dec.window[0] = 0
      end
      local finish = C.get_monotonic_time()
      local bps = (packet_size * npackets) / (finish - start)
      print(("Decapsulation (packet size = %d): %.2f Gbit/s")
            :format(packet_size, gbits(bps)))
   end
end

local pmu = require('lib.pmu')
local has_pmu_counters, err = pmu.is_available()
if not has_pmu_counters then
   io.stderr:write('No PMU available: '..err..'\n')
end

if has_pmu_counters then pmu.setup() end

local function measure(f, iterations)
   local set
   if has_pmu_counters then set = pmu.new_counter_set() end
   local start = C.get_time_ns()
   if has_pmu_counters then pmu.switch_to(set) end
   local res = f(iterations)
   if has_pmu_counters then pmu.switch_to(nil) end
   local stop = C.get_time_ns()
   local ns = tonumber(stop-start)
   local cycles = nil
   if has_pmu_counters then cycles = pmu.to_table(set).cycles end
   return cycles, ns, res
end

local function test_perf(f, iterations, what)
   require('jit').flush()
   io.write(tostring(what or f)..': ')
   io.flush()
   local cycles, ns, res = measure(f, iterations)
   if cycles then
      cycles = cycles/iterations
      io.write(('%.2f cycles, '):format(cycles))
   end
   ns = ns/iterations
   io.write(('%.2f ns per iteration (result: %s)\n'):format(
         ns, tostring(res)))
   return res
end

function hash (key_size)
   if key_size then
      key_size = assert(tonumber(key_size))
   else
      key_size = 4
   end
   local value_t = ffi.typeof("uint8_t[$]", key_size)
   local band = require('bit').band
   local fill = require('ffi').fill

   local function baseline_hash(ptr) return ptr[0] end
   local murmur = require('lib.hash.murmur').MurmurHash3_x86_32:new()
   local function murmur_hash(v)
      return murmur:hash(v, key_size, 0ULL).u32[0]      
   end
   local lib_siphash = require('lib.hash.siphash')
   local sip_hash_1_2_opts = { size=key_size, c=1, d=2 }
   local sip_hash_2_4_opts = { size=key_size, c=2, d=4 }

   local function test_scalar_hash(iterations, hash)
      local value = ffi.new(ffi.typeof('uint8_t[$]', key_size))
      local result
      for i=1,iterations do
	 fill(value, key_size, band(i, 255))
	 result = hash(value)
      end
      return result
   end

   local function test_parallel_hash(iterations, hash, width)
      local value = ffi.new('uint8_t[?]', key_size*width)
      local result = ffi.new('uint32_t[?]', width)
      for i=1,iterations,width do
	 fill(value, key_size*width, band(i+width-1, 255))
	 hash(value, result)
      end
      return result[width-1]
   end

   local function hash_tester(hash)
      return function(iterations)
         return test_scalar_hash(iterations, hash)
      end
   end

   local function sip_hash_tester(opts, width)
      local opts = lib.deepcopy(opts)
      opts.size = key_size
      if width > 1 then
         opts.width = width
         local hash = lib_siphash.make_multi_hash(opts)
	 return function(iterations)
	    return test_parallel_hash(iterations, hash, width)
	 end
      else
         return hash_tester(lib_siphash.make_hash(opts))
      end
   end

   test_perf(hash_tester(baseline_hash), 1e8, 'baseline')
   test_perf(hash_tester(murmur_hash), 1e8, 'murmur hash (32 bit)')
   for _, opts in ipairs({{c=1,d=2}, {c=2,d=4}}) do
      for _, width in ipairs({1,2,4,8}) do
         test_perf(sip_hash_tester(opts, width), 1e8,
                   string.format('sip hash c=%d,d=%d (x%d)',
                                 opts.c, opts.d, width))
      end
   end
end

function ctable ()
   local ctable = require('lib.ctable')
   local bnot = require('bit').bnot
   local ctab = ctable.new(
      { key_type = ffi.typeof('uint32_t[2]'),
        value_type = ffi.typeof('int32_t[5]') })
   local occupancy = 2e6
   ctab:resize(occupancy / 0.4 + 1)

   local function test_insertion(count)
      local k = ffi.new('uint32_t[2]');
      local v = ffi.new('int32_t[5]');
      for i = 1,count do
         k[0], k[1] = i, i
         for j=0,4 do v[j] = bnot(i) end
         ctab:add(k, v)
      end
   end

   local function test_lookup_ptr(count)
      local k = ffi.new('uint32_t[2]');
      local result = ctab.entry_type()
      for i = 1, count do
         k[0], k[1] = i, i
         result = ctab:lookup_ptr(k)
      end
      return result
   end

   local function test_lookup_and_copy(count)
      local k = ffi.new('uint32_t[2]');
      local result = ctab.entry_type()
      for i = 1, count do
         k[0], k[1] = i, i
         ctab:lookup_and_copy(k, result)
      end
      return result
   end

   test_perf(test_insertion, occupancy, 'insertion (40% occupancy)')
   test_perf(test_lookup_ptr, occupancy, 'lookup_ptr (40% occupancy)')
   test_perf(test_lookup_and_copy, occupancy, 'lookup_and_copy (40% occupancy)')

   local stride = 1
   repeat
      local streamer = ctab:make_lookup_streamer(stride)
      local function test_lookup_streamer(count)
         local result
         for i = 1, count, stride do
            local n = math.min(stride, count-i+1)
            for j = 0, n-1 do
               streamer.entries[j].key[0] = i + j
               streamer.entries[j].key[1] = i + j
            end
            streamer:stream()
            result = streamer.entries[n-1].value[0]
         end
         return result
      end
      -- Note that "result" is part of the value, not an index into
      -- the table, and so we expect the results to be different from
      -- ctab:lookup().
      test_perf(test_lookup_streamer, occupancy,
                'streaming lookup, stride='..stride)
      stride = stride * 2
   until stride > 256
end

function selftest ()
   local function test_source ()
      local source = Source:new()
      local src_mac = ethernet:pton("00:00:5E:00:00:01")
      local dst_mac = ethernet:pton("00:00:5E:00:00:02")
      source:set_packet_addresses(src_mac, dst_mac)
      source:set_packet_size(128)
   end
   local function test_set_packet ()
      local source = Source:new()
      local pkt = build_packet({size = 550,
                                src_mac = "00:00:5E:00:00:01",
                                dst_mac = "00:00:5E:00:00:02"})
      source:set_packet(pkt)
   end
   print("selftest:")
   test_source()
   test_set_packet()
   print("ok")
end
