module(..., package.seeall)

local counter = require("core.counter")
local ffi = require("ffi")
local lib = require("core.lib")
local lwcounter = require("apps.lwaftr.lwcounter")
local lwtypes = require("apps.lwaftr.lwtypes")
local lwutil = require("apps.lwaftr.lwutil")
local shm = require("core.shm")
local top = require("program.top.top")

local select_snabb_instance = top.select_snabb_instance
local keys = lwutil.keys

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

local function pidof(maybe_pid)
   if tonumber(maybe_pid) then return maybe_pid end
   local name_id = maybe_pid
   for _, pid in ipairs(shm.children("/")) do
      local path = "/"..pid.."/nic/id"
      if shm.exists(path) then
         local lwaftr_id = shm.open(path, lwtypes.lwaftr_id_type)
         if ffi.string(lwaftr_id.value) == name_id then
            return pid
         end
      end
   end
end

function parse_args (raw_args)
   local handlers = {}
   function handlers.h() show_usage(0) end
   function handlers.l ()
      for _, name in ipairs(sort(lwcounter.counter_names)) do
         print(name)
      end
      main.exit(0)
   end
   local args = lib.dogetopt(raw_args, handlers, "hl",
                             { help="h", ["list-all"]="l" })
   if #args > 2 then show_usage(1) end
   if #args == 2 then
      return args[1], args[2]
   end
   if #args == 1 then
      local arg = args[1]
      if is_counter_name(arg) then
         return nil, arg
      else
         local pid = pidof(arg)
         if not pid then
            error(("Couldn't find PID for argument '%s'"):format(arg))
         end
         return pid, nil
      end
   end
   return nil, nil
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

local function skip_counter (name, filter)
   return filter and not name:match(filter)
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
   local target_pid, counter_name = parse_args(raw_args)
   local instance_tree = select_snabb_instance(target_pid)
   print_counters(instance_tree, counter_name)
end
