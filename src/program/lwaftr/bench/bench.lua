module(..., package.seeall)

local app = require("core.app")
local config = require("core.config")
local lib = require("core.lib")
local csv_stats  = require("program.lwaftr.csv_stats")
local setup = require("program.lwaftr.setup")
local S = require("syscall")

function show_usage(code)
   print(require("program.lwaftr.bench.README_inc"))
   main.exit(code)
end

function parse_args(args)
   local handlers = {}
   local opts = { bench_file = 'bench.csv' }
   local scheduling = {}
   function handlers.D(arg)
      opts.duration = assert(tonumber(arg), "duration must be a number")
      assert(opts.duration >= 0, "duration can't be negative")
   end
   function handlers.cpu(arg)
      local cpu = tonumber(arg)
      if not cpu or cpu ~= math.floor(cpu) or cpu < 0 then
         fatal("Invalid cpu number: "..arg)
      end
      scheduling.cpu = cpu
   end
   function handlers.n(arg) opts.name = assert(arg) end
   function handlers.b(arg) opts.bench_file = arg end
   function handlers.y() opts.hydra = true end
   function handlers.h() show_usage(0) end
   function handlers.reconfigurable() opts.reconfigurable = true end
   args = lib.dogetopt(args, handlers, "n:hyb:D:", {
      help="h", hydra="y", ["bench-file"]="b", duration="D", name="n", cpu=1,
      reconfigurable = 0 })
   if #args ~= 3 then show_usage(1) end
   return opts, scheduling, unpack(args)
end

function run(args)
   local opts, scheduling, conf_file, inv4_pcap, inv6_pcap = parse_args(args)
   local conf = require('apps.lwaftr.conf').load_lwaftr_config(conf_file)

   -- If there is a name defined on the command line, it should override
   -- anything defined in the config.
   if opts.name then
      conf.softwire_config.name = opts.name
   end

   local graph = config.new()
   if opts.reconfigurable then
      setup.reconfigurable(scheduling, setup.load_bench, graph, conf,
                           inv4_pcap, inv6_pcap, 'sinkv4', 'sinkv6')
   else
      setup.apply_scheduling(scheduling)
      setup.load_bench(graph, conf, inv4_pcap, inv6_pcap, 'sinkv4', 'sinkv6')
   end
   app.configure(graph)

   local function start_sampling_for_pid(pid)
      local csv = csv_stats.CSVStatsTimer:new(opts.bench_file, opts.hydra, pid)
      csv:add_app('sinkv4', { 'input' }, { input=opts.hydra and 'decap' or 'Decap.' })
      csv:add_app('sinkv6', { 'input' }, { input=opts.hydra and 'encap' or 'Encap.' })
      csv:activate()
   end
   if opts.reconfigurable then
      for _,pid in ipairs(app.configuration.apps['leader'].arg.follower_pids) do
         -- The worker will be fed its configuration by the
         -- leader, but we don't know when that will all be ready.
         -- Just retry if this doesn't succeed.
         local function start_sampling()
            if not pcall(start_sampling_for_pid, pid) then
               io.stderr:write("Waiting on follower "..pid.." to start "..
                                  "before recording statistics...\n")
               timer.activate(timer.new('retry_csv', start_sampling, 1e9))
            end
         end
         timer.activate(timer.new('spawn_csv_stats', start_sampling, 10e6))
      end
   else
      start_sampling_for_pid(S.getpid())
   end

   if not opts.reconfigurable then
      -- The leader does not need all the CPU, only the followers do.
      app.busywait = true
   end
   app.main({duration=opts.duration})
end
