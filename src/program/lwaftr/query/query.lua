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
   if #args > 1 then show_usage(1) end
   return args[1]
end

function print_counters (tree)
   local cnt, cnt_path, value
   print("lwAFTR operational counters (non-zero)")
   -- Open, read and print whatever counters are in that directory.
   local counters_path = "/" .. tree .. "/" .. counters_rel_dir
   for _, name in ipairs(shm.children(counters_path)) do
      cnt_path = counters_path .. name
      cnt = counter.open(cnt_path, 'readonly')
      value = tonumber(counter.read(cnt))
      if value ~= 0 then
         name = name:gsub(".counter$", "")
         print(name..": "..lib.comma_value(value))
      end
   end
end

function run (raw_args)
   local target_pid = parse_args(raw_args)
   local instance_tree = select_snabb_instance(target_pid)
   print_counters(instance_tree)
end
