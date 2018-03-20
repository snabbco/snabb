-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local engine    = require("core.app")
local app_graph = require("core.config")
local lib       = require("core.lib")
local cpuset    = require("lib.cpuset")
local yang      = require("lib.yang.yang")
local ptree     = require("lib.ptree.ptree")

local function fatal (msg, ...)
   print(string.format(msg, ...))
   main.exit(1)
end

local function show_usage (exit_code)
   print(require("program.ptree.README_inc"))
   if exit_code then main.exit(exit_code) end
end

function parse_args (args)
   local opts = { verbosity = 1, cpuset = cpuset.new() }
   local scheduling = { ingress_drop_monitor = 'flush' }
   local handlers = {}
   function handlers.n (arg) opts.name = assert(arg) end
   function handlers.v () opts.verbosity = opts.verbosity + 1 end
   function handlers.D (arg)
      opts.duration = assert(tonumber(arg), "duration must be a number")
      assert(opts.duration >= 0, "duration can't be negative")
   end
   function handlers.cpu (arg)
      opts.cpuset:add_from_string(arg)
   end
   handlers['real-time'] = function (arg)
      scheduling.real_time = true
   end
   handlers["on-ingress-drop"] = function (arg)
      if arg == 'flush' or arg == 'warn' then
         scheduling.ingress_drop_monitor = arg
      elseif arg == 'off' then
         scheduling.ingress_drop_monitor = false
      else
         fatal("invalid --on-ingress-drop argument: %s (valid values: %s)",
               arg, "flush, warn, off")
      end
   end
   function handlers.j (arg) scheduling.j = arg end
   function handlers.h () show_usage(0) end

   args = lib.dogetopt(args, handlers, "vD:hn:j:",
     { verbose = "v", duration = "D", help = "h", cpu = 1,
       ["real-time"] = 0, ["on-ingress-drop"] = 1,
       name="n" })

   if #args ~= 3 then show_usage(1) end

   return opts, scheduling, unpack(args)
end

function run (args)
   local opts, scheduling, schema_file, setup_file, conf_file = parse_args(args)
   local schema_name = yang.add_schema_file(schema_file)
   local setup_thunk = loadfile(setup_file)
   local conf = yang.load_configuration(conf_file, {schema_name=schema_name})

   local setup_fn = setup_thunk()
   if not type(setup_fn) then
      fatal("Expected %s to evaluate to a function, instead got %s",
            setup_file, tostring(setup_fn))
   end

   local manager = ptree.new_manager {
      name = opts.name,
      setup_fn = setup_fn,
      cpuset = opts.cpuset,
      initial_configuration = conf,
      schema_name = schema_name,
      worker_default_scheduling = scheduling,
      log_level = ({"WARN","INFO","DEBUG"})[opts.verbosity or 1] or "DEBUG",
   }

   manager:main(opts.duration)

   manager:stop()
end
