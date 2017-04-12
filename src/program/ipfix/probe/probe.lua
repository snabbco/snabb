-- This module implements the `snabb flow_export` command

module(..., package.seeall)

local now      = require("core.app").now
local lib      = require("core.lib")
local link     = require("core.link")
local cache    = require("apps.ipfix.cache")
local meter    = require("apps.ipfix.meter")
local exporter = require("apps.ipfix.export")
local numa     = require("lib.numa")

-- apps that can be used as an input or output for the exporter
in_out_apps = {}

function in_out_apps.pcap (path)
   return { input = "input",
            output = "output" },
          { require("apps.pcap.pcap").PcapReader, path }
end

function in_out_apps.raw (device)
   return { input = "rx",
            output = "tx" },
          { require("apps.socket.raw").RawSocket, device }
end

function in_out_apps.intel10g (device)
   local conf = { pciaddr = device }
   return { input = "rx",
            output = "tx" },
          { require("apps.intel.intel_app").Intel82599, conf }
end

local long_opts = {
   help = "h",
   duration = "D",
   port = "p",
   transport = 1,
   stats = "s",
   ["host-mac"] = "m",
   ["host-ip"] = "a",
   ["input-type"] = "i",
   ["output-type"] = "o",
   ["netflow-v9"] = 0,
   ["ipfix"] = 0,
   ["active-timeout"] = 1,
   ["idle-timeout"] = 1,
   ["cpu"] = 1
}

function run (args)
   local duration

   local input_type, output_type = "intel10g", "intel10g"

   local host_mac, host_ip
   local collector_mac, colletor_ip
   local port = 4739

   local active_timeout, idle_timeout
   local ipfix_version = 10

   local cpu
   local report = false

   -- TODO: better input validation
   local opt = {
      h = function (arg)
         print(require("program.ipfix.probe.README_inc"))
         main.exit(0)
      end,
      D = function (arg)
         duration = assert(tonumber(arg), "expected number for duration")
      end,
      i = function (arg)
         assert(in_out_apps[arg], "unknown input type")
         input_type = arg
      end,
      o = function (arg)
         assert(in_out_apps[arg], "unknown output type")
         output_type = arg
      end,
      p = function (arg)
         port = assert(tonumber(arg), "expected number for port")
      end,
      s = function (arg)
         report = true
      end,
      m = function (arg)
         host_mac = arg
      end,
      a = function (arg)
         host_ip = arg
      end,
      c = function (arg)
         collector_ip = arg
      end,
      -- TODO: this should probably be superceded by using ARP
      M = function (arg)
         collector_mac = arg
      end,
      ["active-timeout"] = function (arg)
         active_timeout =
            assert(tonumber(arg), "expected number for active timeout")
      end,
      ["idle-timeout"] = function (arg)
         idle_timeout =
            assert(tonumber(arg), "expected number for idle timeout")
      end,
      ipfix = function (arg)
         ipfix_version = 10
      end,
      ["netflow-v9"] = function (arg)
         ipfix_version = 9
      end,
      -- TODO: not implemented
      ["transport"] = function (arg) end,
      ["cpu"] = function (arg)
         cpu = tonumber(arg)
      end
   }

   args = lib.dogetopt(args, opt, "hsD:i:o:p:m:a:c:M:", long_opts)
   if #args ~= 2 then
      print(require("program.ipfix.probe.README_inc"))
      main.exit(1)
   end

   assert(host_mac, "--host-mac argument required")
   assert(host_ip, "--host-ip argument required")
   assert(collector_ip, "--collector argument required")

   local in_link, in_app   = in_out_apps[input_type](args[1])
   local out_link, out_app = in_out_apps[output_type](args[2])

   local flow_cache      = cache.FlowCache:new({})
   local meter_config    = { cache = flow_cache }
   local exporter_config = { cache = flow_cache,
                             active_timeout = active_timeout,
                             idle_timeout = idle_timeout,
                             ipfix_version = ipfix_version,
                             exporter_mac = host_mac,
                             exporter_ip = host_ip,
                             collector_mac = collector_mac,
                             collector_ip = collector_ip,
                             collector_port = port }
   local c = config.new()

   config.app(c, "source", unpack(in_app))
   config.app(c, "sink", unpack(out_app))
   config.app(c, "meter", meter.FlowMeter, meter_config)
   config.app(c, "exporter", exporter.FlowExporter, exporter_config)

   config.link(c, "source." .. in_link.output .. " -> meter.input")
   config.link(c, "exporter.output -> sink." .. out_link.input)

   local done
   if not duration then
      done = function ()
         return engine.app_table.source.done
      end
   end

   local start_time = now()
   if cpu then numa.bind_to_cpu(cpu) end

   engine.configure(c)
   engine.busywait = true
   engine.main({ duration = duration, done = done })

   if report then
      local end_time = now()
      local app = engine.app_table.meter
      local input_link = app.input.input
      local stats = link.stats(input_link)
      print("IPFIX probe stats:")
      print(string.format("bytes: %s packets: %s bps: %s Mpps: %s",
                          lib.comma_value(stats.rxbytes),
                          lib.comma_value(stats.rxpackets),
                          lib.comma_value(math.floor((stats.rxbytes * 8) / (end_time - start_time))),
                          lib.comma_value(stats.rxpackets / ((end_time - start_time) * 1000000))))
  end
end
