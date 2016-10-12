module(..., package.seeall)

local engine = require("core.app")
local counter = require("core.counter")
local config = require("core.config")
local pci = require("lib.hardware.pci")
local Intel82599 = require("apps.intel.intel_app").Intel82599
local basic_apps = require("apps.basic.basic_apps")
local loadgen = require("apps.lwaftr.loadgen")
local main = require("core.main")
local PcapReader = require("apps.pcap.pcap").PcapReader
local lib = require("core.lib")
local promise = require("program.lwaftr.loadtest.promise")

local WARM_UP_BIT_RATE = 5e9
local WARM_UP_TIME = 2

local function show_usage(code)
   print(require("program.lwaftr.loadtest.README_inc"))
   main.exit(code)
end

local function find_devices(pattern)
   if #pci.devices == 0 then pci.scan_devices() end
   pattern = pci.qualified(pattern)
   local ret = {}
   for _,device in ipairs(pci.devices) do
      if (device.usable and device.driver == 'apps.intel.intel_app' and
          pattern:match(device.pciaddress)) then
         table.insert(ret, device.pciaddress)
      end
   end
   return ret
end

local function find_device(pattern)
   local devices = find_devices(pattern)
   if #devices == 0 then
      error('no devices matched pattern "'..pattern..'"')
   elseif #devices == 1 then
      return devices[1]
   else
      local devices_str = table.concat(devices, ' ')
      error('multiple devices matched pattern "'..pattern..'":'..devices_str)
   end
end

function parse_args(args)
   local handlers = {}
   local opts = { bitrate = 10e9, duration = 5 }
   function handlers.b(arg)
      opts.bitrate = assert(tonumber(arg), 'bitrate must be a number')
   end
   function handlers.s(arg)
      opts.step = assert(tonumber(arg), 'step must be a number')
   end
   function handlers.D(arg)
      opts.duration = assert(tonumber(arg), 'duration must be a number')
   end
   function handlers.h() show_usage(0) end
   args = lib.dogetopt(args, handlers, "hb:s:D:p:",
                       { bitrate="b", step="s", duration="D", help="h" })
   if not opts.step then opts.step = opts.bitrate / 10 end
   assert(opts.bitrate > 0, 'bitrate must be positive')
   assert(opts.step > 0, 'step must be positive')
   assert(opts.duration > 0, 'duration must be positive')
   if #args == 0 or #args % 4 ~= 0 then show_usage(1) end
   local streams = {}
   for i=1,#args,4 do
      local capture_file, tx, rx, pattern = args[i], args[i+1], args[i+2], args[i+3]
      local nic = {
         capture_file = capture_file,
         tx_name = tx,
         rx_name = rx,
         tx_id = tx:gsub('[^%w]', '_'),
         rx_id = rx:gsub('[^%w]', '_'),
         pci_addr = find_device(pattern)
      }
      table.insert(streams, nic)
   end
   return opts, streams
end

local function read_counters(link)
   return {
      txpackets = counter.read(link.stats.input_packets),
      txbytes = counter.read(link.stats.input_bytes)
   }
end

local function diff_counters(a, b)
   return {
      txpackets = tonumber(b.txpackets - a.txpackets),
      txbytes = tonumber(b.txbytes - a.txbytes)
   }
end

function run(args)
   local opts, streams = parse_args(args)
   local c = config.new()
   for _,stream in ipairs(streams) do
      stream.pcap_id = 'pcap_'..stream.tx_id
      stream.repeater_id = 'repeater_'..stream.tx_id
      stream.nic_tx_id = 'nic_'..stream.tx_id
      stream.nic_rx_id = 'nic_'..stream.rx_id
      stream.rx_sink_id = 'rx_sink_'..stream.rx_id

      config.app(c, stream.pcap_id, PcapReader, stream.capture_file)
      config.app(c, stream.repeater_id, loadgen.RateLimitedRepeater, {})
      config.app(c, stream.nic_tx_id, Intel82599, { pciaddr = stream.pci_addr })
      config.app(c, stream.rx_sink_id, basic_apps.Sink)

      config.link(c, stream.pcap_id..".output -> "..stream.repeater_id..".input")
      config.link(c, stream.repeater_id..".output -> "..stream.nic_tx_id..".input")

      config.link(c, stream.nic_rx_id..".output -> "..stream.rx_sink_id..".input")
   end
   engine.configure(c)

   local function adjust_rates(bit_rate)
      local byte_rate = bit_rate / 8
      for _,stream in ipairs(streams) do
         local app = engine.app_table[stream.repeater_id]
         app:set_rate(byte_rate)
      end
   end

   local function generate_load(bitrate, duration)
      adjust_rates(bitrate)
      return promise.Wait(duration):and_then(adjust_rates, 0)
   end

   local function warm_up()
      print(string.format("Warming up at %f Gb/s for %s seconds.",
                          WARM_UP_BIT_RATE / 1e9, WARM_UP_TIME))
      return generate_load(WARM_UP_BIT_RATE, WARM_UP_TIME):
         and_then(promise.Wait, 0.5)
   end

   local function record_counters()
      local ret = {}
      for _, stream in ipairs(streams) do
         local tx_nic = assert(engine.app_table[stream.nic_tx_id],
                               "NIC "..stream.nic_tx_id.." not found")
         local rx_nic = assert(engine.app_table[stream.nic_rx_id],
                               "NIC "..stream.nic_rx_id.." not found")
         ret[stream.nic_tx_id] = {
            tx = read_counters(tx_nic.input.input),
            rx = read_counters(rx_nic.output.output)
         }
      end
      return ret
   end

   local function print_counter_diff(before, after)
      for _, stream in ipairs(streams) do
         print(string.format('  %s:', stream.tx_name))
         local nic_id = stream.nic_tx_id
         local nic_before, nic_after = before[nic_id], after[nic_id]
         local tx = diff_counters(nic_before.tx, nic_after.tx)
         local rx = diff_counters(nic_before.rx, nic_after.rx)
         print(string.format('    TX %d packets (%f MPPS), %d bytes (%f Gbps)',
                             tx.txpackets, tx.txpackets / opts.duration / 1e6,
                             tx.txbytes, tx.txbytes / opts.duration / 1e9 * 8))
         print(string.format('    RX %d packets (%f MPPS), %d bytes (%f Gbps)',
                             rx.txpackets, rx.txpackets / opts.duration / 1e6,
                             rx.txbytes, rx.txbytes / opts.duration / 1e9 * 8))
         print(string.format('    Loss: %d packets (%f%%)',
                             tx.txpackets - rx.txpackets,
                             (tx.txpackets - rx.txpackets) / tx.txpackets * 100))
      end
   end

   local function measure(bitrate)
      local start_counters = record_counters()
      local function report()
         local end_counters = record_counters()
         print_counter_diff(start_counters, end_counters)
      end
      print(string.format('Applying %f Gbps of load.', bitrate/1e9))
      return generate_load(bitrate, opts.duration):
         -- Wait 2ms for packets in flight to arrive
         and_then(promise.Wait, 0.002):
         and_then(report)
   end

   local function run_tests()
      local head = promise.new()
      local tail = head
      for step = 1, math.ceil(opts.bitrate / opts.step) do
         tail = tail:and_then(measure, math.min(opts.bitrate, opts.step * step))
      end
      head:resolve()
      return tail
   end

   local function run_engine(p)
      local is_done = false
      local function mark_done() is_done = true end
      p:and_then(mark_done)

      local function done() return is_done end
      engine.main({done=done})
   end

   engine.busywait = true
   run_engine(warm_up():and_then(run_tests))
end
