-- This module implements the `snabb flow_export` command

module(..., package.seeall)

local lib  = require("core.lib")
local flow = require("apps.flow_export.flow_export")

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
   ["host-mac"] = "m",
   ["host-ip"] = "a",
   ["input-type"] = "i",
   ["output-type"] = "o",
   ["netflow-v9"] = 0,
   ["ipfix"] = 0,
   ["active-timeout"] = 1,
   ["idle-timeout"] = 1
}

function run (args)
   local duration

   local input_type, output_type = "intel10g", "intel10g"

   local host_mac, host_ip
   local collector_mac, colletor_ip
   local port = 4739

   local active_timeout, idle_timeout

   -- TODO: better input validation
   local opt = {
      h = function (arg)
         print(require("program.flow_export.README_inc"))
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
      -- TODO: not implemented
      ipfix = function (arg) end,
      ["netflow-v9"] = function (arg) end,
      ["transport"] = function (arg) end
   }

   args = lib.dogetopt(args, opt, "hD:i:o:p:m:a:c:M:", long_opts)
   if #args ~= 2 then
      print(require("program.flow_export.README_inc"))
      main.exit(1)
   end

   assert(host_mac, "--host-mac argument required")
   assert(host_ip, "--host-ip argument required")
   assert(collector_ip, "--collector argument required")

   local in_link, in_app   = in_out_apps[input_type](args[1])
   local out_link, out_app = in_out_apps[output_type](args[2])

   local exporter_config = { active_timeout = active_timeout,
                             idle_timeout = idle_timeout,
                             exporter_mac = host_mac,
                             exporter_ip = host_ip,
                             collector_mac = collector_mac,
                             collector_ip = collector_ip,
                             collector_port = port }
   local c = config.new()

   config.app(c, "source", unpack(in_app))
   config.app(c, "sink", unpack(out_app))
   config.app(c, "exporter", flow.FlowExporter, exporter_config)

   config.link(c, "source." .. in_link.output .. " -> exporter.input")
   config.link(c, "exporter.output -> sink." .. out_link.input)

   local done
   if not duration then
      done = function ()
         return engine.app_table.source.done
      end
   end

   engine.configure(c)
   engine.busywait = true
   engine.main({ duration = duration, done = done })
end
