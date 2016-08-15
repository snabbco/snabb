module(..., package.seeall)

local S = require("syscall")
local counter = require("core.counter")
local lib = require("core.lib")
local lwaftr = require("apps.lwaftr.lwaftr")
local shm = require("core.shm")
local top = require("program.top.top")

local select_snabb_instance = top.select_snabb_instance

-- Get the counter dir from the code.
local counters_rel_dir = lwaftr.counters_dir

function show_usage (code)
   print(require("program.lwaftr.query.README_inc"))
   main.exit(code)
end

function parse_args (raw_args)
   local handlers = {}
   function handlers.h() show_usage(0) end
   local args = lib.dogetopt(raw_args, handlers, "h", { help="h" })
   if #args > 2 then show_usage(1) end
   return args
end

function print_counters (tree, filter)
   local cnt, cnt_path, value
   print("lwAFTR operational counters (non-zero)")
   -- Open, read and print whatever counters are in that directory.
   local counters_path = "/" .. tree .. "/" .. counters_rel_dir
   local counters = shm.children(counters_path)
   table.sort(counters)
   for _, name in ipairs(counters) do
      cnt_path = counters_path .. name
      cnt = counter.open(cnt_path, 'readonly')
      value = tonumber(counter.read(cnt))
      if value ~= 0 then
         name = name:gsub(".counter$", "")
         if filter then
            if name:match(filter) then
               print(name..": "..lib.comma_value(value))
            end
         else
            print(name..": "..lib.comma_value(value))
         end
      end
   end
end

function run (raw_args)
   local args = parse_args(raw_args) 

   local target_pid, counter_name
   if #args == 2 then
      target_pid, counter_name = args[1], args[2]
   elseif #args == 1 then
      local maybe_pid = tonumber(args[1])
      if maybe_pid then
         target_pid = args[1]
      else
         counter_name = args[1]
      end
   end

   local instance_tree = select_snabb_instance(target_pid)
   print_counters(instance_tree, counter_name)
end
