-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local lib   = require("core.lib")
local now   = require("core.app").now
local timer = require("core.timer")
local ipv4  = require("lib.protocol.ipv4")
local ipv6  = require("lib.protocol.ipv6")
local util  = require("apps.wall.util")
local scan  = require("apps.wall.scanner")
local const = require("apps.wall.constants")
local proto = require("ndpi").protocol
local comm  = require("program.wall.common")
local ntohs = lib.ntohs

local long_opts = {
   help = "h",
   live = "l",
   stats = "s",
   duration = "D",
}

local function printf(fmt, ...)
   io.write(fmt:format(...))
end

local function report_flow(scanner, flow)
   local lo_addr, hi_addr = "<unknown>", "<unknown>"
   local eth_type = flow.key:eth_type()
   if eth_type == const.ETH_TYPE_IPv4 then
      lo_addr = ipv4:ntop(flow.key.lo_addr)
      hi_addr = ipv4:ntop(flow.key.hi_addr)
   elseif eth_type == const.ETH_TYPE_IPv6 then
      lo_addr = ipv6:ntop(flow.key.lo_addr)
      hi_addr = ipv6:ntop(flow.key.hi_addr)
   end

   if flow.proto_master ~= proto.PROTOCOL_UNKNOWN then
      printf("%#010x %4dp %15s:%-5d - %15s:%-5d  %s:%s\n",
         flow.key:hash(), flow.packets,
         lo_addr, ntohs(flow.key.lo_port),
         hi_addr, ntohs(flow.key.hi_port),
         scanner:protocol_name(flow.protocol),
         scanner:protocol_name(flow.proto_master))
   else
      printf("%#010x %4dp %15s:%-5d - %15s:%-5d  %s\n",
         flow.key:hash(), flow.packets,
         lo_addr, ntohs(flow.key.lo_port),
         hi_addr, ntohs(flow.key.hi_port),
         scanner:protocol_name(flow.protocol))
   end
end

local function report_summary(scanner)
   for flow in scanner:flows() do
      report_flow(scanner, flow)
   end
end

local LiveReporter = setmetatable({}, util.SouthAndNorth)
LiveReporter.__index = LiveReporter

function LiveReporter:new (scanner)
   return setmetatable({ scanner = scanner }, self)
end

function LiveReporter:on_northbound_packet (p)
   local flow = self.scanner:get_flow(p)
   if flow and not flow.reported then
      local proto = self.scanner:protocol_name(flow.protocol)
      if proto:lower() ~= "unknown" then
         report_flow(self.scanner, flow)
         flow.reported = true
      end
   end
   return p
end
LiveReporter.on_southbound_packet = LiveReporter.on_northbound_packet


local StatsReporter = setmetatable({}, util.SouthAndNorth)
StatsReporter .__index = StatsReporter

function StatsReporter:new (opts)
   local app = setmetatable({
      scanner = opts.scanner,
      file = opts.output or io.stdout,
      start_time = now(),
      packets = 0,
      bytes = 0,
      timer = false,
   }, self)
   if opts.period then
      app.timer = timer.new("stats_reporter",
                            function () app:report_stats() end,
                            opts.period * 1e9)
      timer.activate(app.timer)
   end
   return app
end

function StatsReporter:stop ()
   -- Avoid timer being re-armed in the next call to :on_timer_tick()
   self.timer = false
end

function StatsReporter:on_northbound_packet (p)
   self.packets = self.packets + 1
   self.bytes = self.bytes + p.length
   return p
end
StatsReporter.on_southbound_packet = StatsReporter.on_northbound_packet

local stats_format = "=== %s === %d Bytes, %d packets, %.3f B/s, %.3f PPS\n"
function StatsReporter:report_stats ()
   local cur_time = now()
   local elapsed = cur_time - self.start_time

   self.file:write(stats_format:format(os.date("%Y-%m-%dT%H:%M:%S%z"),
                                       self.bytes,
                                       self.packets,
                                       self.bytes / elapsed,
                                       self.packets / elapsed))
   self.file:flush()

   -- Reset counters.
   self.packets, self.bytes, self.start_time = 0, 0, cur_time

   -- Re-arm timer.
   if self.timer then
      timer.activate(self.timer)
   end
end


local function setup_input(c, input_spec)
   local kind, arg = input_spec_pattern:match(input_spec)
   if not kind then
      kind, arg = "pcap", input_spec
   end
   if not comm.inputs[kind] then
      return nil, "No such input kind: " .. kind
   end
   return comm.inputs[kind](kind, arg)
end


function run (args)
   local live, stats = false, false
   local duration
   local opt = {
      l = function (arg)
         live = true
      end,
      s = function (arg)
         stats = true
      end,
      h = function (arg)
         print(require("program.wall.spy.README_inc"))
         main.exit(0)
      end,
      D = function (arg)
         duration = tonumber(arg)
      end
   }

   args = lib.dogetopt(args, opt, "hlsD:", long_opts)
   if #args ~= 2 then
      print(require("program.wall.spy.README_inc"))
      main.exit(1)
   end

   if not comm.inputs[args[1]] then
      io.stderr:write("No such input available: ", args[1], "\n")
      main.exit(1)
   end

   local source_link_name, app = comm.inputs[args[1]](args[1], args[2])
   if not source_link_name then
      io.stderr:write(app, "\n")
      main.exit(1)
   end

   -- FIXME: When multiple scanners are available, allow selecting others.
   local s = require("apps.wall.scanner.ndpi"):new()

   local c = config.new()
   config.app(c, "source", unpack(app))
   config.app(c, "l7spy", require("apps.wall.l7spy").L7Spy, { scanner = s })
   config.link(c, "source." .. source_link_name .. " -> l7spy.south")
   local last_app_name = "l7spy"

   if stats then
      config.app(c, "stats", StatsReporter, {
         scanner = s, period = live and 2.0 or false })
      config.link(c, last_app_name .. ".north -> stats.south")
      last_app_name = "stats"
   end

   if live then
      config.app(c, "report", LiveReporter, s)
      config.link(c, last_app_name .. ".north -> report.south")
      last_app_name = "report"
   end

   local done
   if not duration then
      done = function ()
         return engine.app_table.source.done
      end
   end

   engine.configure(c)
   engine.busywait = true
   engine.main {
      duration = duration,
      done = done
   }

   if not live then
      report_summary(s)
   end
   if stats then
      engine.app_table.stats:report_stats()
   end
end
