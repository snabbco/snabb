module(..., package.seeall)

local counter = require("core.counter")
local lib = require("core.lib")
local shm = require("core.shm")
local S = require("syscall")

-- Get the counter dir from the code.
local counters_rel_dir = require("apps.lwaftr.lwaftr").counters_dir

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

-- TODO: taken from program/top/top.lua, unify somewhere.
function select_snabb_instance (pid)
   local instances = shm.children("//")
   if pid then
      -- Try to use the given pid.
      for _, instance in ipairs(instances) do
         if instance == pid then return pid end
      end
      print("No such Snabb instance: "..pid)
   elseif #instances == 2 then
      -- Two means one is us, so we pick the other.
      local own_pid = tostring(S.getpid())
      if instances[1] == own_pid then return instances[2]
      else                            return instances[1] end
   elseif #instances == 1 then print("No Snabb instance found.")
   else print("Multiple Snabb instances found. Select one.") end
   os.exit(1)
end

function print_counters (tree)
   local cnt, cnt_path, value
   print("lwAFTR operational counters (non-zero)")
   -- Open, read and print whatever counters are in that directory.
   local counters_path = tree .. "/" .. counters_rel_dir
   for _, name in ipairs(shm.children(counters_path)) do
      cnt_path = counters_path .. name
      cnt = counter.open(cnt_path, 'readonly')
      value = tonumber(counter.read(cnt))
      if value ~= 0 then
         print(name..": "..value)
      end
   end
end

function run (raw_args)
   local target_pid = parse_args(raw_args)
   local instance_tree = "//"..(select_snabb_instance(target_pid))
   print_counters(instance_tree)
end
