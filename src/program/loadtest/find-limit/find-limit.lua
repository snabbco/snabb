module(..., package.seeall)

local engine = require("core.app")
local counter = require("core.counter")
local config = require("core.config")
local pci = require("lib.hardware.pci")
local basic_apps = require("apps.basic.basic_apps")
local loadgen = require("apps.lwaftr.loadgen")
local main = require("core.main")
local PcapReader = require("apps.pcap.pcap").PcapReader
local lib = require("core.lib")
local numa = require("lib.numa")
local promise = require("program.loadtest.promise")

local WARM_UP_BIT_RATE = 1e9
local WARM_UP_TIME = 5

local function show_usage(code)
   print(require("program.loadtest.find_limit.README_inc"))
   main.exit(code)
end

local function find_limit(tester, max_bitrate, precision, duration, retry_count)
   local function round(x)
      return math.floor((x + precision/2) / precision) * precision
   end

   -- lo and hi are bitrates, in bits per second.
   local function bisect(lo, hi, iter)
      local function continue(cur, result)
         if result then
            print("Success.")
            return bisect(cur, hi, 1)
         elseif iter <= retry_count then
            print("Failed; "..(retry_count - iter).. " retries remaining.")
            return bisect(lo, hi, iter + 1)
         else
            print("Failed.")
            return bisect(lo, cur, 1)
         end
      end
      local cur = round((lo + hi) / 2)
      if cur == lo or cur == hi then
         print(round(lo) * 1e-9)
         return lo
      end
      return tester.start_load(cur, duration):
         and_then(continue, cur)
   end
   return bisect(0, round(max_bitrate), 1)
end

local function parse_args(args)
   local opts = { max_bitrate = 10e9, duration = 1, precision = 0.001e9,
                  retry_count = 3 }
   local function parse_positive_number(prop)
      return function(arg)
         local val = assert(tonumber(arg), prop.." must be a number")
         assert(val > 0, prop.." must be positive")
         opts[prop] = val
      end
   end
   local function parse_nonnegative_integer(prop)
      return function(arg)
         local val = assert(tonumber(arg), prop.." must be a number")
         assert(val >= 0, prop.." must be non-negative")
         assert(val == math.floor(val), prop.." must be an integer")
         opts[prop] = val
      end
   end
   local function parse_string(prop)
      return function(arg) opts[prop] = assert(arg) end
   end
   local handlers = { b = parse_positive_number("max_bitrate"),
                      e = parse_string("exec"),
                      D = parse_positive_number("duration"),
                      p = parse_positive_number("precision"),
                      r = parse_nonnegative_integer("retry_count"),
                      cpu = parse_nonnegative_integer("cpu") }
   function handlers.h() show_usage(0) end
   args = lib.dogetopt(args, handlers, "hb:D:p:r:e:",
                       { bitrate="b", duration="D", precision="p",
                         ["retry-count"]="r", help="h", cpu=1,
                         exec="e"})

   if #args == 2 then
      args = {
         args[2],
         'NIC', 'NIC',
         args[1]
      }
   end
   if #args == 0 or #args % 4 ~= 0 then show_usage(1) end
   local streams, streams_by_tx_id, pci_devices = {}, {}, {}
   for i=1,#args,4 do
      local stream = {}
      stream.pcap_file = args[i]
      stream.tx_name = args[i+1]
      stream.rx_name = args[i+2]
      stream.tx_id = stream.tx_name:gsub('[^%w]', '_')
      stream.rx_id = stream.rx_name:gsub('[^%w]', '_')
      stream.tx_device = pci.device_info(args[i+3])
      stream.tx_driver = require(stream.tx_device.driver).driver
      table.insert(streams, stream)
      table.insert(pci_devices, stream.tx_device.pciaddress)
      assert(streams_by_tx_id[streams.tx_id] == nil, 'Duplicate: '..stream.tx_name)
      streams_by_tx_id[stream.tx_id] = stream
   end
   for _, stream in ipairs(streams) do
      assert(streams_by_tx_id[stream.rx_id], 'Missing stream: '..stream.rx_id)
      stream.rx_device = streams_by_tx_id[stream.rx_id].tx_device
   end
   if opts.cpu then numa.bind_to_cpu(opts.cpu) end
   numa.check_affinity_for_pci_addresses(pci_devices)
   return opts, streams
end

function run(args)
   local opts, streams = parse_args(args)

   local c = config.new()
   for _, stream in ipairs(streams) do
      stream.pcap_id     = 'pcap_'..stream.tx_id
      stream.repeater_id = 'repeater'..stream.tx_id
      stream.nic_tx_id   = 'nic_'..stream.tx_id
      stream.nic_rx_id   = 'nic_'..stream.rx_id
      -- Links are named directionally with respect to NIC apps, but we
      -- want to name tx and rx with respect to the whole network
      -- function.
      stream.nic_tx_link = stream.tx_device.rx
      stream.nic_rx_link = stream.rx_device.tx
      stream.rx_sink_id  = 'rx_sink_'..stream.rx_id

      config.app(c, stream.pcap_id, PcapReader, stream.pcap_file)
      config.app(c, stream.repeater_id, loadgen.RateLimitedRepeater)
      config.app(c, stream.nic_tx_id, stream.tx_driver, { pciaddr = stream.tx_device.pciaddress})
      config.app(c, stream.rx_sink_id, basic_apps.Sink)

      config.link(c, stream.pcap_id..".output -> "..stream.repeater_id..".input")
      config.link(c, stream.repeater_id..".output -> "..stream.nic_tx_id.."."..stream.nic_tx_link)
      config.link(c, stream.nic_rx_id.."."..stream.nic_rx_link.." -> "..stream.rx_sink_id..".input")
   end

   engine.configure(c)

   local function read_counters()
      local counters = {}
      for _, stream in ipairs(streams) do
         local tx_app = assert(engine.app_table[stream.nic_tx_id])
         local rx_app = assert(engine.app_table[stream.nic_rx_id])
         local tx, rx = tx_app.input[stream.nic_tx_link], rx_app.output[stream.nic_rx_link]
         counters[stream.nic_tx_id] = {
            txpackets = counter.read(tx.stats.txpackets),
            txbytes = counter.read(tx.stats.txbytes),
            txdrop = counter.read(tx.stats.txdrop) + tx_app:txdrop(),
            rxpackets = counter.read(rx.stats.txpackets),
            rxbytes = counter.read(rx.stats.txbytes),
            rxdrop = rx_app:rxdrop()
         }
      end
      return counters
   end

   local function print_stats(s)
   end

   local function check_results(stats)
      if opts.exec then
         return os.execute(opts.exec) == 0
      end

      local success = true
      for _, stream in ipairs(streams) do
         local diff = stats[stream.nic_tx_id]
         success = (diff.rxpackets >= diff.txpackets)
            and diff.rxdrop == 0 and diff.txdrop == 0
            and success
      end
      return success
   end

   local tester = {}

   function tester.adjust_rates(bit_rate)
      for _, stream in ipairs(streams) do
         local app = assert(engine.app_table[stream.repeater_id])
         app:set_rate(bit_rate)
      end
   end

   function tester.generate_load(bitrate, duration)
      tester.adjust_rates(bitrate)
      return promise.Wait(duration):and_then(tester.adjust_rates, 0)
   end

   function tester.warm_up()
      print(string.format("Warming up at %f Gb/s for %s seconds.",
                          WARM_UP_BIT_RATE / 1e9, WARM_UP_TIME))
      return tester.generate_load(WARM_UP_BIT_RATE, WARM_UP_TIME)
   end

   local function compute_bitrate(packets, bytes, duration)
      -- 7 bytes preamble, 1 start-of-frame, 4 CRC, 12 interframe gap.
      local overhead = 7 + 1 + 4 + 12
      return (bytes + packets * overhead) * 8 / duration
   end

   function tester.start_load(bitrate, duration)
      return tester.generate_load(WARM_UP_BIT_RATE, 1):
	 and_then(promise.Wait, 0.002):
	 and_then(tester.measure, bitrate, duration)
   end

   function tester.measure(bitrate, duration)
      local gbps_bitrate = bitrate/1e9
      local start_counters = read_counters()
      local function compute_stats()
         local end_counters = read_counters()
         local stats = {}
         for _, stream in ipairs(streams) do
            local s = {}
            for k,_ in pairs(start_counters[stream.nic_tx_id]) do
               local end_value = end_counters[stream.nic_tx_id][k]
               local start_value = start_counters[stream.nic_tx_id][k]
               s[k] = tonumber(end_value - start_value)
            end
            s.applied_gbps = gbps_bitrate
            s.tx_mpps = s.txpackets / duration / 1e6
            s.tx_gbps = compute_bitrate(s.txpackets, s.txbytes, duration) / 1e9
            s.rx_mpps = s.rxpackets / duration / 1e6
            s.rx_gbps = compute_bitrate(s.rxpackets, s.rxbytes, duration) / 1e9
            s.lost_packets = (s.txpackets - s.rxpackets) - s.rxdrop
            s.lost_percent = (s.txpackets - s.rxpackets) / s.txpackets * 100
            print(string.format('  %s:', stream.tx_name))
            print(string.format('    TX %d packets (%f MPPS), %d bytes (%f Gbps)',
                       s.txpackets, s.tx_mpps, s.txbytes, s.tx_gbps))
            print(string.format('    RX %d packets (%f MPPS), %d bytes (%f Gbps)',
                       s.rxpackets, s.rx_mpps, s.rxbytes, s.rx_gbps))
            print(string.format('    Loss: %d ingress drop + %d packets lost (%f%%)',
                       s.rxdrop, s.lost_packets, s.lost_percent))

            stats[stream.nic_tx_id] = s
         end
         return stats
      end
      local function verify_load(stats)
         for _, stream in ipairs(streams) do
           local s = stats[stream.nic_tx_id]
            if s.tx_gbps < 0.5 * s.applied_gbps then
               print("Invalid result.")
               return tester.start_load(bitrate, duration)
            end
         end
         return check_results(stats)
      end
      print(string.format('Applying %f Gbps of load.', gbps_bitrate))
      return tester.generate_load(bitrate, duration):
         -- Wait 2ms for packets in flight to arrive
         and_then(promise.Wait, 0.002):
	 and_then(compute_stats):
	 and_then(verify_load)
   end

   io.stdout:setvbuf("line")

   engine.busywait = true
   local is_done = false
   local function mark_done() is_done = true end
   tester.warm_up():
      and_then(find_limit, tester, opts.max_bitrate, opts.precision,
               opts.duration, opts.retry_count):
      and_then(mark_done)
   engine.main({done=function() return is_done end})
end
