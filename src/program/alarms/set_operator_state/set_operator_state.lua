-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local common = require("program.config.common")

function show_usage(command, status, err_msg)
   if err_msg then print('error: '..err_msg) end
   print(require("program.alarms.set_operator_state.README_inc"))
   main.exit(status)
end

local function fatal()
   show_usage(nil, 1)
end

local function parse_args (args)
   if #args < 4 or #args > 5 then fatal() end
   local alarm_type_id, alarm_type_qualifier = (args[3]):match("([%w]+)/([%w]+)")
   if not alarm_type_id then
      alarm_type_id, alarm_type_qualifier = args[3], ''
   end
   local ret = {
      key = {
         resource = args[2],
         alarm_type_id = alarm_type_id,
         alarm_type_qualifier = alarm_type_qualifier,
      },
      state = args[4],
      text = args[5] or '',
   }
   -- Remove all arguments except first one.
   for i=2,#args do
      table.remove(args, #args)
   end
   return ret
end

function run(args)
   local l_args = parse_args(args)
   local opts = { command='set-alarm-operator-state', with_path=false, is_config=false,
                  usage = show_usage }
   args = common.parse_command_line(args, opts)
   local response = common.call_leader(
      args.instance_id, 'set-alarm-operator-state',
      { schema = args.schema_name, revision = args.revision_date,
        resource = l_args.key.resource, alarm_type_id = l_args.key.alarm_type_id,
        alarm_type_qualifier = l_args.key.alarm_type_qualifier,
        state = l_args.state, text = l_args.text })
   common.print_and_exit(response, "success")
end
