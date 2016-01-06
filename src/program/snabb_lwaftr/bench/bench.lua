module(..., package.seeall)

local app = require("core.app")
local basic_apps = require("apps.basic.basic_apps")
local config = require("core.config")
local lib = require("core.lib")
local pcap = require("apps.pcap.pcap")
local lwaftr = require("apps.lwaftr.lwaftr")

function show_usage(code)
   print(require("program.snabb_lwaftr.bench.README_inc"))
   main.exit(code)
end

function parse_args(args)
   local handlers = {}
   local opts = {}
   function handlers.D(arg)
      opts.duration = assert(tonumber(arg), "duration must be a number")
      assert(opts.duration >= 0, "duration can't be negative")
   end
   function handlers.h() show_usage(0) end
   args = lib.dogetopt(args, handlers, "hD:", { help="h", duration="D" })
   if #args ~= 3 then show_usage(1) end
   return opts, unpack(args)
end

function run(args)
   local opts, conf_file, inv4_pcap, inv6_pcap = parse_args(args)

   local c = config.new()
   config.app(c, "capturev4", pcap.PcapReader, inv4_pcap)
   config.app(c, "capturev6", pcap.PcapReader, inv6_pcap)
   config.app(c, "repeaterv4", basic_apps.Repeater)
   config.app(c, "repeaterv6", basic_apps.Repeater)
   config.app(c, "lwaftr", lwaftr.LwAftr, conf_file)
   config.app(c, "statisticsv4", basic_apps.Statistics)
   config.app(c, "statisticsv6", basic_apps.Statistics)
   config.app(c, "sinkv4", basic_apps.Sink)
   config.app(c, "sinkv6", basic_apps.Sink)

   config.link(c, "capturev4.output -> repeaterv4.input")
   config.link(c, "repeaterv4.output -> lwaftr.v4")
   config.link(c, "lwaftr.v4 -> statisticsv4.input")
   config.link(c, "statisticsv4.output -> sinkv4.input")

   config.link(c, "capturev6.output -> repeaterv6.input")
   config.link(c, "repeaterv6.output -> lwaftr.v6")
   config.link(c, "lwaftr.v6 -> statisticsv6.input")
   config.link(c, "statisticsv6.output -> sinkv6.input")

   app.configure(c)
   app.main({duration=opts.duration})
end
