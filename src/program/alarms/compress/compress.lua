-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local common = require("program.config.common")

function show_usage(command, status, err_msg)
   if err_msg then print('error: '..err_msg) end
   print(require("program.alarms.compress.README_inc"))
   main.exit(status)
end

local function fatal()
   show_usage(nil, 1)
end

local function parse_args (args)
   if #args ~= 3 then fatal() end
   local resource = args[2]
   local alarm_type_id, alarm_type_qualifier = (args[3]):match("([^/]+)")
   if not alarm_type_id then
      alarm_type_id = args[3]
   end
   for i=2,#args do
      table.remove(args)
   end
   return {
      resource = resource,
      alarm_type_id = alarm_type_id,
      alarm_type_qualifier = alarm_type_qualifier,
   }
end

function run(args)
   local l_args = parse_args(args)
   local opts = { command='compress-alarms', with_path=false, is_config=false,
                  usage=show_usage }
   args = common.parse_command_line(args, opts)
   if args.error then
      common.print_and_exit(args)
   end
   local response = common.call_leader(
      args.instance_id, 'compress-alarms',
      { schema = args.schema_name, revision = args.revision,
        resource = l_args.resource, alarm_type_id = l_args.alarm_type_id,
        alarm_type_qualifier = l_args.alarm_type_qualifier,
        print_default = args.print_default, format = args.format })
   common.print_and_exit(response, 'compressed_alarms')
end
