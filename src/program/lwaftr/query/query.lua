module(..., package.seeall)

local engine = require("core.app")
local counter = require("core.counter")
local lib = require("core.lib")
local shm = require("core.shm")
local data = require("lib.yang.data")
local schema = require("lib.yang.schema")
local state = require("lib.yang.state")
local counters = require("program.lwaftr.counters")
local lwutil = require("apps.lwaftr.lwutil")
local top = require("program.top.top")
local ps = require("program.ps.ps")

local keys, fatal = lwutil.keys, lwutil.fatal

function show_usage (code)
   print(require("program.lwaftr.query.README_inc"))
   main.exit(code)
end

local function sort (t)
   table.sort(t)
   return t
end

function parse_args (raw_args)
   local handlers = {}
   local opts = {}
   local name
   function handlers.h() show_usage(0) end
   function handlers.l ()
      for _, name in ipairs(sort(keys(counters.counter_names()))) do
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

local function max_key_width (counters)
   local max_width = 0
   for name, value in pairs(counters) do
      if value ~= 0 then
         if #name > max_width then max_width = #name end
      end
   end
   return max_width
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

local function print_counters (pid, filter)
   print("lwAFTR operational counters (non-zero)")
   -- Open, read and print whatever counters are in that directory.
   local counters = counters.read_counters(pid)
   local max_width = max_key_width(counters)
   for _, name in ipairs(sort(keys(counters))) do
      if not skip_counter(name, filter) then
         local value = counters[name]
         if value ~= 0 then
            print_counter(name, value, max_width)
         end
      end
   end
end

-- Return the pid that was specified, unless it was a manager process,
-- in which case, return the worker pid that actually has useful
-- counters.
local function pid_to_parent(pid)
   -- It's meaningless to get the parent of a nil 'pid'.
   if not pid then return pid end
   local pid = tonumber(pid)
   for _, name in ipairs(shm.children("/")) do
      local p = tonumber(name)
      if p and ps.is_worker(p) then
         local manager_pid = tonumber(ps.get_manager_pid(p))
         -- If the precomputed by-name pid is the manager pid, set the
         -- pid to be the worker's pid instead to get meaningful
         -- counters.
         if manager_pid == pid then pid = p end
      end
   end
   return pid
end

function run (raw_args)
   local opts, arg1, arg2 = parse_args(raw_args)
   local pid, counter_name
   if not opts.name then
      if arg1 then pid = pid_to_parent(arg1) end
      counter_name = arg2 -- This may be nil
   else -- by-name: arguments are shifted by 1 and no pid is specified
      counter_name = arg1
      -- Start by assuming it was run without --reconfigurable
      local programs = engine.enumerate_named_programs(opts.name)
      pid = programs[opts.name]
      if not pid then
         fatal(("Couldn't find process with name '%s'"):format(opts.name))
      end

      -- Check if it was run with --reconfigurable If it was, find the
      -- children, then find the pid of their parent.  Note that this
      -- approach will break as soon as there can be multiple workers
      -- which need to have their statistics aggregated, as it will only
      -- print the statistics for one child, not for all of them.
      for _, name in ipairs(shm.children("/")) do
         local p = tonumber(name)
         if p and ps.is_worker(p) then
            local manager_pid = tonumber(ps.get_manager_pid(p))
            -- If the precomputed by-name pid is the manager pid, set
            -- the pid to be the worker's pid instead to get meaningful
            -- counters.
            if manager_pid == pid then pid = p end
         end
      end
   end
   if not pid then
      top.select_snabb_instance(pid)
      -- The following is not reached when there are multiple instances.
      fatal("Please manually specify a pid, or a name with -n name")
   end
   print_counters(pid, counter_name)
end
