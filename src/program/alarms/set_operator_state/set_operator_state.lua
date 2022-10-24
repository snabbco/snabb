-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local common = require("program.config.common")

function show_usage(program, status, err_msg)
   if err_msg then print('error: '..err_msg) end
   print(require("program.alarms.set_operator_state.README_inc"))
   main.exit(status)
end

local function fatal()
   show_usage('set-operator-state', 1)
end

local function parse_args (args)
   if #args < 3 or #args > 4 then fatal() end
   local alarm_type_id, alarm_type_qualifier = (args[2]):match("([%w]+)/([%w]+)")
   if not alarm_type_id then
      alarm_type_id, alarm_type_qualifier = args[2], ''
   end
   local ret = {
      key = {
         resource = args[1],
         alarm_type_id = alarm_type_id,
         alarm_type_qualifier = alarm_type_qualifier,
      },
      state = args[3],
      text = args[4] or '',
   }
   return ret
end

function run(args)
   local opts = { command='set-alarm-operator-state', with_path=false, is_config=false,
                  usage=show_usage, allow_extra_args=true }
   local args, cdr = common.parse_command_line(args, opts)
   if args.error then
      common.print_and_exit(args)
   end
   local l_args = parse_args(cdr)
   local response = common.call_leader(
      args.instance_id, 'set-alarm-operator-state',
      { schema = args.schema_name, revision = args.revision_date,
        resource = l_args.key.resource, alarm_type_id = l_args.key.alarm_type_id,
        alarm_type_qualifier = l_args.key.alarm_type_qualifier,
        state = l_args.state, text = l_args.text })
   common.print_and_exit(response, "success")
end
