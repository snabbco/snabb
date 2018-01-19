-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local common = require("program.config.common")
local lib = require("core.lib")

function show_usage(command, status, err_msg)
   if err_msg then print('error: '..err_msg) end
   print(require("program.alarms.purge.README_inc"))
   main.exit(status)
end

local function fatal()
   show_usage(nil, 1)
end

local function parse_args (args)
   local handlers = {}
   local opts = {}
   local function table_size (t)
      local count = 0
      for _ in pairs(t) do count = count + 1 end
      return count
   end
   local function without_opts (args)
      local ret = {}
      for i=1,#args do
         local arg = args[i]
         if opts[arg] then
            i = i + 2
         else
            table.insert(ret, arg)
         end
      end
      return ret
   end
   handlers['by-older-than'] = function (arg) opts.older_than = arg end
   handlers['by-severity'] = function (arg) opts.severity = arg end
   handlers['by-operator-state'] = function (arg)
      opts.operator_state_filter = arg
   end
   args = lib.dogetopt(args, handlers, "", { ['by-older-than']=1,
      ['by-severity']=1, ['by-operator-state']=1 })
   opts.status = table.remove(args, #args)
   if table_size(opts) == 0 then fatal() end
   local args = without_opts(args)
   return opts, args
end

function run(args)
   local l_args, args = parse_args(args)
   local opts = { command='purge-alarms', with_path=false, is_config=false,
                  usage = show_usage }
   args = common.parse_command_line(args, opts)
   local response = common.call_leader(
      args.instance_id, 'purge-alarms',
      { schema = args.schema_name, alarm_status = l_args.status,
        older_than = l_args.older_than, severity = l_args.severity,
        operator_state_filter = l_args.operator_state_filter,
        print_default = args.print_default, format = args.format })
   common.print_and_exit(response, "purged_alarms")
end
