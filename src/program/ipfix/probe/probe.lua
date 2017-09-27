-- This module implements the `snabb flow_export` command

module(..., package.seeall)

local now      = require("core.app").now
local lib      = require("core.lib")
local link     = require("core.link")
local shm      = require("core.shm")
local counter  = require("core.counter")
local basic    = require("apps.basic.basic_apps")
local arp      = require("apps.ipv4.arp")
local ipfix    = require("apps.ipfix.ipfix")
local pci      = require("lib.hardware.pci")
local ipv4     = require("lib.protocol.ipv4")
local ethernet = require("lib.protocol.ethernet")
local macaddress = require("lib.macaddress")
local numa     = require("lib.numa")
local S        = require("syscall")

-- apps that can be used as an input or output for the exporter
local in_apps, out_apps = {}, {}

local function parse_spec (spec, delimiter)
   local t = {}
   for s in spec:split(delimiter or ':') do
      table.insert(t, s)
   end
   return t
end

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

function out_apps.tap_routed (device)
   return { input = "input",
            output = "output" },
          { require("apps.tap.tap").Tap, { name = device } }
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

function in_apps.pci (spec)
   local device, rxq = unpack(parse_spec(spec, '/'))
   local device_info = pci.device_info(device)
   local conf = { pciaddr = device }
   if device_info.driver == 'apps.intel_mp.intel_mp' then
      local rxq = (rxq and tonumber(rxq)) or 0
      conf.rxq = rxq
      conf.rxcounter = rxq
      conf.ring_buffer_size = 32768
   end
   return { input = device_info.rx, output = device_info.tx },
          { require(device_info.driver).driver, conf }
end
out_apps.pci = in_apps.pci

local long_opts = {
   help = "h",
   jit = "j",
   duration = "D",
   port = "p",
   transport = 1,
   ["host-ip"] = "a",
   ["input-type"] = "i",
   ["output-type"] = "o",
   ["mtu"] = 1,
   ["netflow-v9"] = 0,
   ["ipfix"] = 0,
   ["active-timeout"] = 1,
   ["idle-timeout"] = 1,
   ["observation-domain"] = 1,
   ["template-refresh"] = 1,
   ["flush-timeout"] = 1,
   ["cache-size"] = 1,
   ["scan-time"] = 1,
   ["pfx-to-as"] = 1,
   ["maps-log"] = 1,
   ["vlan-to-ifindex"] = 1,
   ["mac-to-as"] = 1,
   ["cpu"] = 1,
   ["busy-wait"] = "b"
}

function run (args)
   local duration
   local busywait = false
   local traceprofiling = false
   local jit_opts = {}

   local input_type, output_type = "pci", "pci"

   local host_mac
   local host_ip = '10.0.0.1' -- Just to have a default.
   local collector_ip = '10.0.0.2' -- Likewise.
   local port = 4739
   local mtu = 1514

   local active_timeout, idle_timeout, flush_timeout, scan_time
   local observation_domain, template_refresh_interval
   local cache_size
   local ipfix_version = 10
   local templates = {}
   local maps = {}
   local maps_log_fh

   local pfx_to_as, vlan_to_ifindex, mac_to_as

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
      b = function (arg)
         busywait = true
      end,
      ["active-timeout"] = function (arg)
         active_timeout =
            assert(tonumber(arg), "expected number for active timeout")
      end,
      ["idle-timeout"] = function (arg)
         idle_timeout =
            assert(tonumber(arg), "expected number for idle timeout")
      end,
      ["flush-timeout"] = function (arg)
         flush_timeout =
            assert(tonumber(arg), "expected number for flush timeout")
      end,
      ["scan-time"] = function (arg)
         scan_time =
            assert(tonumber(arg), "expected number for scan time")
      end,
      ["observation-domain"] = function (arg)
         observation_domain =
            assert(tonumber(arg), "expected number for observation domain")
      end,
      ["template-refresh"] = function (arg)
         template_refresh_interval =
            assert(tonumber(arg), "expected number for template refresh interval")
      end,
      ["cache-size"] = function (arg)
         cache_size =
            assert(tonumber(arg), "expected number for cache size")
      end,
      ["pfx-to-as"] = function (arg)
         if arg then
            maps.pfx_to_as = arg
         end
      end,
      ["vlan-to-ifindex"] = function (arg)
         if arg then
            maps.vlan_to_ifindex = arg
         end
      end,
      ["mac-to-as"] = function (arg)
         if arg then
            maps.mac_to_as = arg
         end
      end,
      ["maps-log"] = function (arg)
         if arg then
            maps_log_fh = assert(io.open(arg, "a"))
         end
      end,
      ipfix = function (arg)
         ipfix_version = 10
      end,
      ["netflow-v9"] = function (arg)
         ipfix_version = 9
      end,
      ["mtu"] = function (arg)
         mtu = tonumber(arg)
      end,
      -- TODO: not implemented
      ["transport"] = function (arg) end,
      ["cpu"] = function (arg)
         cpu = tonumber(arg)
      end,
      j = function (arg)
         if arg:match("^v") then
            local file = arg:match("^v=(.*)")
            if file == '' then file = nil end
            require("jit.v").start(file)
         elseif arg:match("^p") then
            local opts, file = arg:match("^p=([^,]*),?(.*)")
            if file == '' then file = nil end
            require("jit.p").start(opts, file)
            profiling = true
         elseif arg:match("^dump") then
            local opts, file = arg:match("^dump=([^,]*),?(.*)")
            if file == '' then file = nil end
            require("jit.dump").on(opts, file)
         elseif arg:match("^opt") then
            local opt = arg:match("^opt=(.*)")
            table.insert(jit_opts, opt)
         elseif arg:match("^tprof") then
            require("lib.traceprof.traceprof").start()
            traceprofiling = true
         end
      end
   }

   args = lib.dogetopt(args, opt, "hD:i:o:p:m:a:c:j:b", long_opts)
   if #args < 2 then
      print(require("program.ipfix.probe.README_inc"))
      main.exit(1)
   elseif #args == 2 then
      table.insert(args, 'v4')
      table.insert(args, 'v6')
   end

   local in_link, in_app   = in_apps[input_type](args[1])
   local out_link, out_app = out_apps[output_type](args[2])

   for i = 3, #args do
      table.insert(templates, args[i])
   end

   local arp_config    = { self_mac = host_mac and ethernet:pton(host_mac),
                           self_ip = ipv4:pton(host_ip),
                           next_ip = ipv4:pton(collector_ip) }
   local function mk_ipfix_config()
      return { active_timeout = active_timeout,
               idle_timeout = idle_timeout,
               flush_timeout = flush_timeout,
               cache_size = cache_size,
               scan_time = scan_time,
               observation_domain = observation_domain,
               template_refresh_interval = template_refresh_interval,
               ipfix_version = ipfix_version,
               exporter_ip = host_ip,
               collector_ip = collector_ip,
               collector_port = port,
               mtu = mtu - 14,
               templates = templates,
               maps = maps,
               maps_log_fh = maps_log_fh }
   end
   local ipfix_config = mk_ipfix_config()
   if output_type == "tap_routed" then
      tap_config = out_app[2]
      tap_config.mtu = mtu
   end
   local c = config.new()

   config.app(c, "in", unpack(in_app))
   config.app(c, "ipfix", ipfix.IPFIX, ipfix_config)
   config.app(c, "out", unpack(out_app))

   -- use ARP for link-layer concerns unless the output is connected
   -- to a pcap writer
   if output_type ~= "pcap" and output_type ~= "tap_routed" then
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
      config.app(c, "sink", basic.Sink)
      config.link(c, "out." .. out_link.output .. " -> sink.input")
   end

   local done
   if not duration and input_type == "pcap" then
      done = function ()
         return engine.app_table['in'].done
      end
   end

   local t1 = now()
   if cpu then numa.bind_to_cpu(cpu) end

   engine.configure(c)

   if output_type == "tap_routed" then
      local tap_config = out_app[2]
      local name = tap_config.name
      local tap_sysctl_base = "net/ipv4/conf/"..name
      assert(S.sysctl(tap_sysctl_base.."/rp_filter", '0'))
      assert(S.sysctl(tap_sysctl_base.."/accept_local", '1'))
      assert(S.sysctl(tap_sysctl_base.."/forwarding", '1'))
      local export_stats = engine.app_table.out.shm
      local ipfix_config = mk_ipfix_config()
      ipfix_config.exporter_eth_dst =
         tostring(macaddress:new(counter.read(export_stats.macaddr)))
      config.app(c, "ipfix", ipfix.IPFIX, ipfix_config)
      engine.configure(c)
   end
   engine.busywait = busywait
   if #jit_opts then
      require("jit.opt").start(unpack(jit_opts))
   end
   engine.main({ duration = duration, done = done, measure_latency = false })
   if traceprofiling then
      require("lib.traceprof.traceprof").stop()
   end

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
