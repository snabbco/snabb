-- This module implements the `snabb flow_export` command

module(..., package.seeall)

local now      = require("core.app").now
local lib      = require("core.lib")
local link     = require("core.link")
local basic    = require("apps.basic.basic_apps")
local arp      = require("apps.ipv4.arp")
local ipfix    = require("apps.ipfix.ipfix")
local pci      = require("lib.hardware.pci")
local ipv4     = require("lib.protocol.ipv4")
local ethernet = require("lib.protocol.ethernet")
local numa     = require("lib.numa")

-- apps that can be used as an input or output for the exporter
local in_apps, out_apps = {}, {}

function in_apps.pcap (path)
   return { input = "input",
            output = "output" },
          { require("apps.pcap.pcap").PcapReader, path }
end

function out_apps.pcap (path)
   return { input = "input",
            output = "output" },
          { require("apps.pcap.pcap").PcapWriter, path }
end

function in_apps.raw (device)
   return { input = "rx",
            output = "tx" },
          { require("apps.socket.raw").RawSocket, device }
end
out_apps.raw = in_apps.raw

function in_apps.tap (device)
   return { input = "input",
            output = "output" },
          { require("apps.tap.tap").Tap, device }
end
out_apps.tap = in_apps.tap

function in_apps.pci (device)
   local device_info = pci.device_info(device)
   local conf = { pciaddr = device }
   return { input = device_info.rx, output = device_info.tx },
          { require(device_info.driver).driver, conf }
end
out_apps.pci = in_apps.pci

local long_opts = {
   help = "h",
   duration = "D",
   port = "p",
   transport = 1,
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

   local input_type, output_type = "pci", "pci"

   local host_mac
   local host_ip = '10.0.0.1' -- Just to have a default.
   local collector_ip = '10.0.0.2' -- Likewise.
   local port = 4739

   local active_timeout, idle_timeout
   local ipfix_version = 10

   local cpu

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
         assert(in_apps[arg], "unknown input type")
         input_type = arg
      end,
      o = function (arg)
         assert(out_apps[arg], "unknown output type")
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

   args = lib.dogetopt(args, opt, "hD:i:o:p:m:a:c:", long_opts)
   if #args ~= 2 then
      print(require("program.ipfix.probe.README_inc"))
      main.exit(1)
   end

   local in_link, in_app   = in_apps[input_type](args[1])
   local out_link, out_app = out_apps[output_type](args[2])

   local arp_config    = { self_mac = host_mac and ethernet:pton(host_mac),
                           self_ip = ipv4:pton(host_ip),
                           next_ip = ipv4:pton(collector_ip) }
   local ipfix_config    = { active_timeout = active_timeout,
                             idle_timeout = idle_timeout,
                             ipfix_version = ipfix_version,
                             exporter_ip = host_ip,
                             collector_ip = collector_ip,
                             collector_port = port }
   local c = config.new()

   config.app(c, "in", unpack(in_app))
   config.app(c, "ipfix", ipfix.IPFIX, ipfix_config)
   config.app(c, "out", unpack(out_app))

   -- use ARP for link-layer concerns unless the output is connected
   -- to a pcap writer
   if output_type ~= "pcap" then
      config.app(c, "arp", arp.ARP, arp_config)
      config.app(c, "sink", basic.Sink)

      config.link(c, "in." .. in_link.output .. " -> ipfix.input")
      config.link(c, "out." .. out_link.output .. " -> arp.south")

      -- with UDP, ipfix doesn't need to handle packets from the collector
      config.link(c, "arp.north -> sink.input")

      config.link(c, "ipfix.output -> arp.north")
      config.link(c, "arp.south -> out." .. out_link.input)
   else
      config.link(c, "in." .. in_link.output .. " -> ipfix.input")
      config.link(c, "ipfix.output -> out." .. out_link.input)
   end

   local done
   if not duration then
      done = function ()
         return engine.app_table["in"].done
      end
   end

   local t1 = now()
   if cpu then numa.bind_to_cpu(cpu) end

   engine.configure(c)
   engine.busywait = true
   engine.main({ duration = duration, done = done })

   local t2 = now()
   local stats = link.stats(engine.app_table.ipfix.input.input)
   print("IPFIX probe stats:")
   local comma = lib.comma_value
   print(string.format("bytes: %s packets: %s bps: %s Mpps: %s",
                       comma(stats.rxbytes),
                       comma(stats.rxpackets),
                       comma(math.floor((stats.rxbytes * 8) / (t2 - t1))),
                       comma(stats.rxpackets / ((t2 - t1) * 1000000))))
end
