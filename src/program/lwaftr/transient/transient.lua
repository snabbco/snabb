module(..., package.seeall)

local engine = require("core.app")
local config = require("core.config")
local timer = require("core.timer")
local csv_stats = require("program.lwaftr.csv_stats")
local pci = require("lib.hardware.pci")
local Intel82599 = require("apps.intel.intel_app").Intel82599
local basic_apps = require("apps.basic.basic_apps")
local loadgen = require("apps.lwaftr.loadgen")
local main = require("core.main")
local PcapReader = require("apps.pcap.pcap").PcapReader
local lib = require("core.lib")

function show_usage(code)
   print(require("program.lwaftr.transient.README_inc"))
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
   local opts = {
      bitrate = 10e9, duration = 5, period = 1, bench_file = 'bench.csv' }
   function handlers.b(arg)
      opts.bitrate = assert(tonumber(arg), 'bitrate must be a number')
   end
   function handlers.s(arg)
      opts.step = assert(tonumber(arg), 'step must be a number')
   end
   function handlers.D(arg)
      opts.duration = assert(tonumber(arg), 'duration must be a number')
   end
   function handlers.p(arg)
      opts.period = assert(tonumber(arg), 'period must be a number')
   end
   handlers["bench-file"] = function(bench_file)
      opts.bench_file = bench_file
   end
   function handlers.h() show_usage(0) end
   args = lib.dogetopt(args, handlers, "hb:s:D:p:",
                       { bitrate="b", step="s", duration="D", period="p",
                         ["bench-file"]=1, help="h" })
   if not opts.step then opts.step = opts.bitrate / 10 end
   assert(opts.bitrate > 0, 'bitrate must be positive')
   assert(opts.step > 0, 'step must be positive')
   assert(opts.duration > 0, 'duration must be positive')
   assert(opts.period > 0, 'period must be positive')
   if #args == 0 or #args % 3 ~= 0 then show_usage(1) end
   local streams = {}
   for i=1,#args,3 do
      local capture_file, name, pattern = args[i], args[i+1], args[i+2]
      local nic = {
         capture_file = capture_file,
         name = name,
         id = name:gsub('[^%w]', '_'),
         pci_addr = find_device(pattern)
      }
      table.insert(streams, nic)
   end
   return opts, streams
end

-- This ramps the repeater up from 0 Gbps to the max bitrate, lingering
-- at the top only for one period, then comes back down in the same way.
-- We can add more of these for different workloads.
local function adjust_rate(opts, streams)
   local count = math.ceil(opts.bitrate / opts.step)
   return function()
      local bitrate = opts.bitrate - math.abs(count) * opts.step
      for _,stream in ipairs(streams) do
         local app = engine.app_table[stream.repeater_id]
         app:set_rate(bitrate)
      end
      count = count - 1
   end
end

function run(args)
   local opts, streams = parse_args(args)
   local c = config.new()
   for _,stream in ipairs(streams) do
      stream.pcap_id = 'pcap_'..stream.id
      stream.repeater_id = 'repeater_'..stream.id
      stream.nic_id = 'nic_'..stream.id
      stream.rx_sink_id = 'rx_sink_'..stream.id

      config.app(c, stream.pcap_id, PcapReader, stream.capture_file)
      config.app(c, stream.repeater_id, loadgen.RateLimitedRepeater, {})
      config.app(c, stream.nic_id, Intel82599, { pciaddr = stream.pci_addr })
      config.app(c, stream.rx_sink_id, basic_apps.Sink)

      config.link(c, stream.pcap_id..".output -> "..stream.repeater_id..".input")
      config.link(c, stream.repeater_id..".output -> "..stream.nic_id..".rx")

      config.link(c, stream.nic_id..".tx -> "..stream.rx_sink_id..".input")
   end
   engine.configure(c)

   local rate_adjuster = adjust_rate(opts, streams)
   -- Initialize rates before anything happens.
   rate_adjuster()
   timer.activate(timer.new("adjust_rate", rate_adjuster,
                            opts.duration * 1e9, 'repeating'))
   local csv = csv_stats.CSVStatsTimer:new(opts.bench_file)
   for _,stream in ipairs(streams) do
      csv:add_app(stream.nic_id, { 'rx', 'tx' },
                  { rx=stream.name..' TX', tx=stream.name..' RX' })
   end
   csv:activate()
   engine.busywait = true
   engine.main({duration=opts.duration*((opts.bitrate/opts.step)*2+1)})
end
