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
local WARM_UP_TIME = 1

local function fatal (msg)
   print(msg)
   main.exit(1)
end

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
      if cur == lo or cur == hi then return lo end
      return tester.measure(cur, duration):
         and_then(continue, cur)
   end
   return bisect(0, round(max_bitrate), 1)
end

function parse_args(args)
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
   if #args ~= 2 then show_usage(1) end
   local device, capture_file = unpack(args)
   if opts.cpu then numa.bind_to_cpu(opts.cpu) end
   numa.check_affinity_for_pci_addresses({device})
   return opts, device, capture_file
end

function run(args)
   local opts, device, capture_file = parse_args(args)
   local device_info = pci.device_info(device)
   local driver = require(device_info.driver).driver
   local c = config.new()

   -- Links are named directionally with respect to NIC apps, but we
   -- want to name tx and rx with respect to the whole network
   -- function.
   local tx_link_name = device_info.rx
   local rx_link_name = device_info.tx

   config.app(c, "replay", PcapReader, capture_file)
   config.app(c, "repeater", loadgen.RateLimitedRepeater, {})
   config.app(c, "nic", driver, { pciaddr = device_info.pciaddress })
   config.app(c, "blackhole", basic_apps.Sink)

   config.link(c, "replay.output -> repeater.input")
   config.link(c, "repeater.output -> nic."..tx_link_name)
   config.link(c, "nic."..rx_link_name.." -> blackhole.input")

   engine.configure(c)

   local nic_app = assert(engine.app_table.nic)
   local repeater_app = assert(engine.app_table.repeater)

   local function read_counters()
      local tx, rx = nic_app.input[tx_link_name], nic_app.output[rx_link_name]
      return { txpackets = counter.read(tx.stats.txpackets),
               txbytes = counter.read(tx.stats.txbytes),
               rxpackets = counter.read(rx.stats.txpackets),
               rxbytes = counter.read(rx.stats.txbytes),
               rxdrop = nic_app:rxdrop() }
   end

   local function print_diff(diff, duration)
      local function bitrate(packets, bytes)
         -- 7 bytes preamble, 1 start-of-frame, 4 CRC, 12 interframe gap.
         local overhead = 7 + 1 + 4 + 12
         return (bytes + packets * overhead) * 8 / duration
      end
      local tx_mpps = diff.txpackets / duration / 1e6
      local tx_gbps = bitrate(diff.txpackets, diff.txbytes) / 1e9
      local rx_mpps = diff.rxpackets / duration / 1e6
      local rx_gbps = bitrate(diff.rxpackets, diff.rxbytes) / 1e9
      local lost_packets = diff.txpackets - diff.rxpackets - diff.rxdrop
      local lost_percent = lost_packets / diff.txpackets * 100
      print(string.format('    TX %d packets (%f MPPS), %d bytes (%f Gbps)',
                          diff.txpackets, tx_mpps, diff.txbytes, tx_gbps))
      print(string.format('    RX %d packets (%f MPPS), %d bytes (%f Gbps)',
                          diff.rxpackets, rx_mpps, diff.rxbytes, rx_gbps))
      print(string.format('    Loss: %d ingress drop + %d packets lost (%f%%)',
                          diff.rxdrop, lost_packets, lost_percent))
   end

   local function check_results(diff)
      if opts.exec then
         -- Could pass on some arguments to this string.
         return os.execute(opts.exec) == 0
      else
         return diff.rxpackets == diff.txpackets and diff.rxdrop == 0
      end
   end

   local tester = {}

   function tester.adjust_rates(bit_rate)
      repeater_app:set_rate(bit_rate)
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

   function tester.measure(bitrate, duration)
      local gbps_bitrate = bitrate/1e9
      local start_counters = read_counters()
      local function report()
         local end_counters = read_counters()
         local diff = {}
         for k,v in pairs(start_counters) do
            diff[k] = tonumber(end_counters[k] - start_counters[k])
         end
         print_diff(diff, duration)
         return diff
      end
      print(string.format('Applying %f Gbps of load.', gbps_bitrate))
      return tester.generate_load(bitrate, duration):
         -- Wait 2ms for packets in flight to arrive
         and_then(promise.Wait, 0.002):
         and_then(report):
         and_then(check_results)
   end

   engine.busywait = true
   local is_done = false
   local function mark_done() is_done = true end
   tester.warm_up():
      and_then(find_limit, tester, opts.max_bitrate, opts.precision,
               opts.duration, opts.retry_count):
      and_then(mark_done)
   engine.main({done=function() return is_done end})
end
