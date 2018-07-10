module(..., package.seeall)

local app = require("core.app")
local config = require("core.config")
local lib = require("core.lib")
local cpuset = require("lib.cpuset")
local csv_stats  = require("program.lwaftr.csv_stats")
local setup = require("program.lwaftr.setup")
local shm = require("core.shm")
local S = require("syscall")


function show_usage(code)
   print(require("program.lwaftr.bench.README_inc"))
   main.exit(code)
end

function parse_args(args)
   local handlers = {}
   local opts = {}
   local scheduling = {}
   function handlers.D(arg)
      opts.duration = assert(tonumber(arg), "duration must be a number")
      assert(opts.duration >= 0, "duration can't be negative")
   end
   function handlers.cpu(arg)
      cpuset.global_cpuset():add_from_string(arg)
   end
   function handlers.n(arg) opts.name = assert(arg) end
   function handlers.b(arg) opts.bench_file = arg end
   function handlers.y() opts.hydra = true end
   function handlers.j(arg) scheduling.j = arg end
   function handlers.h() show_usage(0) end
   args = lib.dogetopt(args, handlers, "j:n:hyb:D:", {
      help="h", hydra="y", ["bench-file"]="b", duration="D", name="n", cpu=1})
   if #args ~= 3 then show_usage(1) end
   return opts, scheduling, unpack(args)
end

function run(args)
   local opts, scheduling, conf_file, inv4_pcap, inv6_pcap = parse_args(args)
   local conf = setup.read_config(conf_file)

   -- If there is a name defined on the command line, it should override
   -- anything defined in the config.
   if opts.name then
      conf.softwire_config.name = opts.name
   end

   local function setup_fn(graph, lwconfig)
      return setup.load_bench(graph, lwconfig, inv4_pcap, inv6_pcap, 'sinkv4',
			      'sinkv6')
   end

   local manager = setup.ptree_manager(scheduling, setup_fn, conf)

   local stats = {csv={}}
   function stats:worker_starting(id) end
   function stats:worker_started(id, pid)
      local csv = csv_stats.CSVStatsTimer:new(opts.bench_file, opts.hydra, pid)
      csv:add_app('sinkv4', { 'input' }, { input=opts.hydra and 'decap' or 'Decap.' })
      csv:add_app('sinkv6', { 'input' }, { input=opts.hydra and 'encap' or 'Encap.' })
      self.csv[id] = csv
      self.csv[id]:start()
   end
   function stats:worker_stopping(id)
      self.csv[id]:stop()
      self.csv[id] = nil
   end
   function stats:worker_stopped(id) end
   manager:add_state_change_listener(stats)

   manager:main(opts.duration)
   manager:stop()
end
