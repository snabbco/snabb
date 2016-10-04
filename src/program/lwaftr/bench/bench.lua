module(..., package.seeall)

local app = require("core.app")
local config = require("core.config")
local lib = require("core.lib")
local csv_stats  = require("program.lwaftr.csv_stats")
local setup = require("program.lwaftr.setup")

function show_usage(code)
   print(require("program.lwaftr.bench.README_inc"))
   main.exit(code)
end

function parse_args(args)
   local handlers = {}
   local opts = {}
   opts.filename = "bench.csv"
   function handlers.D(arg)
      opts.duration = assert(tonumber(arg), "duration must be a number")
      assert(opts.duration >= 0, "duration can't be negative")
   end
   function handlers.f(arg) opts.filename = arg end
   function handlers.y() opts.hydra = true end
   function handlers.h() show_usage(0) end
   args = lib.dogetopt(args, handlers, "hyf:D:", {
      help="h", hydra="y", filename="f", duration="D" })
   if #args ~= 3 then show_usage(1) end
   return opts, unpack(args)
end

function run(args)
   local opts, conf_file, inv4_pcap, inv6_pcap = parse_args(args)
   local conf = require('apps.lwaftr.conf').load_lwaftr_config(conf_file)

   local c = config.new()
   setup.load_bench(c, conf, inv4_pcap, inv6_pcap, 'sinkv4', 'sinkv6')
   app.configure(c)

   local csv = csv_stats.CSVStatsTimer:new(opts.filename, opts.hydra)
   csv:add_app('sinkv4', { 'input' }, { input=opts.hydra and 'decap' or 'Decap.' })
   csv:add_app('sinkv6', { 'input' }, { input=opts.hydra and 'encap' or 'Encap.' })
   csv:activate()

   app.busywait = true
   app.main({duration=opts.duration})
end
