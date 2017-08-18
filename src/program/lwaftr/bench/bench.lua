module(..., package.seeall)

local app = require("core.app")
local config = require("core.config")
local lib = require("core.lib")
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
   args = lib.dogetopt(args, handlers, "n:hyb:D:", {
      help="h", hydra="y", ["bench-file"]="b", duration="D", name="n", cpu=1})
   if #args ~= 3 then show_usage(1) end
   return opts, scheduling, unpack(args)
end

-- Finds current followers for leader (note it puts the pid as the key)
local function find_followers()
   local followers = {}
   local mypid = S.getpid()
   for _, name in ipairs(shm.children("/")) do
      local pid = tonumber(name)
      if pid ~= nil and shm.exists("/"..pid.."/group") then
         local path = S.readlink(shm.root.."/"..pid.."/group")
         local parent = tonumber(lib.basename(lib.dirname(path)))
         if parent == mypid then
            followers[pid] = true
         end
      end
   end
   return followers
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
   setup.reconfigurable(scheduling, setup.load_bench, graph, conf,
			inv4_pcap, inv6_pcap, 'sinkv4', 'sinkv6')
   app.configure(graph)

   local function start_sampling_for_pid(pid)
      local csv = csv_stats.CSVStatsTimer:new(opts.bench_file, opts.hydra, pid)
      csv:add_app('sinkv4', { 'input' }, { input=opts.hydra and 'decap' or 'Decap.' })
      csv:add_app('sinkv6', { 'input' }, { input=opts.hydra and 'encap' or 'Encap.' })
      csv:activate()
   end
   
   -- We don't know the followers PIDs until the leader starts them. There may
   -- be additional followers started as instances that have been added or
   -- removed during the running. We need to look for the PIDs and start
   -- sampling for each new PID we find.
   local function start_sampling()
      local followers = {}
      local function cycle()
         local new_followers = find_followers()
         for pid, _ in pairs(new_followers) do
            if followers[pid] == nil then
               if not pcall(start_sampling_for_pid, pid) then
                  new_followers[pid] = nil
                  --io.stderr:write("Waiting on follower "..pid.." to start "..
                  --   "before recording statistics...\n")
               end
            end
         end
         followers = new_followers
         
         timer.activate(timer.new('start_sampling', cycle, 1e9))
      end
      timer.activate(timer.new('start_sampling', cycle, 1e9))
   end
   
   start_sampling()
   
   app.main({duration=opts.duration})
end
