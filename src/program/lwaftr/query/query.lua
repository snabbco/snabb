module(..., package.seeall)

local S = require("syscall")
local counter = require("core.counter")
local lib = require("core.lib")
local lwcounter = require("apps.lwaftr.lwcounter")
local lwutil = require("apps.lwaftr.lwutil")
local shm = require("core.shm")
local top = require("program.top.top")
local app = require("core.app")
local ps = require("program.ps.ps")

local keys, fatal = lwutil.keys, lwutil.fatal

-- Get the counter dir from the code.
local counters_dir = lwcounter.counters_dir

function show_usage (code)
   print(require("program.lwaftr.query.README_inc"))
   main.exit(code)
end

local function sort (t)
   table.sort(t)
   return t
end

local function is_counter_name (name)
   return lwcounter.counter_names[name] ~= nil
end

function parse_args (raw_args)
   local handlers = {}
   local opts = {}
   local name
   function handlers.h() show_usage(0) end
   function handlers.l ()
      for _, name in ipairs(sort(lwcounter.counter_names)) do
         print(name)
      end
      main.exit(0)
   end
   function handlers.n (arg)
      opts.name = assert(arg)
   end
   local args = lib.dogetopt(raw_args, handlers, "hln:",
                             { help="h", ["list-all"]="l", name="n" })
   if #args > 2 then show_usage(1) end
   return opts, unpack(args)
end

local function read_counters (tree)
   local ret = {}
   local cnt, cnt_path, value
   local max_width = 0
   local counters_path = "/" .. tree .. "/" .. counters_dir
   local counters = shm.children(counters_path)
   for _, name in ipairs(counters) do
      cnt_path = counters_path .. name
      cnt = counter.open(cnt_path, 'readonly')
      value = tonumber(counter.read(cnt))
      if value ~= 0 then
         name = name:gsub(".counter$", "")
         if #name > max_width then max_width = #name end
         ret[name] = value
      end
   end
   return ret, max_width
end

-- Filters often contain '-', which is a special character for match.
-- Escape it.
local function skip_counter (name, filter)
   local escaped_filter = filter
   if escaped_filter then escaped_filter = filter:gsub("-", "%%-") end
   return filter and not name:match(escaped_filter)
end

local function print_counter (name, value, max_width)
   local nspaces = max_width - #name
   print(("%s: %s%s"):format(name, (" "):rep(nspaces), lib.comma_value(value)))
end

local function print_counters (tree, filter)
   print("lwAFTR operational counters (non-zero)")
   -- Open, read and print whatever counters are in that directory.
   local counters, max_width = read_counters(tree)
   for _, name in ipairs(sort(keys(counters))) do
      if not skip_counter(name, filter) then
         local value = counters[name]
         print_counter(name, value, max_width)
      end
   end
end

function run (raw_args)
   local opts, pid, counter_name = parse_args(raw_args)
   if tostring(pid) and not counter_name then
      counter_name, pid = nil, pid
   end
   if opts.name then
   end
   if opts.name then
      -- Start by assuming it was run without --reconfigurable
      local programs = engine.enumerate_named_programs(opts.name)
      pid = programs[opts.name]
      if not pid then
         fatal(("Couldn't find process with name '%s'"):format(opts.name))
      end

      -- Check if it was run with --reconfigurable
      -- If it was, find the children, then find the pid of their parent.
      -- Note that this approach will break as soon as there can be multiple
      -- followers which need to have their statistics aggregated, as it will
      -- only print the statistics for one child, not for all of them.
      for _, name in ipairs(shm.children("/")) do
         local p = tonumber(name)
         local name = ps.appname_resolver(p)
         if p and ps.is_worker(p) then
            local leader_pid = tonumber(ps.get_leader_pid(p))
            -- If the precomputed by-name pid is the leader pid, set the pid
            -- to be the follower's pid instead to get meaningful counters.
            if leader_pid == pid then pid = p end
         end
      end
   end
   if not pid then fatal("No pid or name specified") end
   local instance_tree = top.select_snabb_instance(pid)
   print_counters(instance_tree, counter_name)
end
