-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local common = require("program.config.common")

local function usage(exit_code)
   print(require('program.config.compress_alarms.README_inc'))
   main.exit(exit_code)
end

local function parse_args (args)
   local function parse_key (key)
      local t = {}
      for each in key:gmatch('([^/]+)') do
         table.insert(t, each)
      end
      return {
         resource = t[1],
         alarm_type_id = t[2],
         alarm_type_qualifier = t[3] or '',
      }
   end
   if #args ~= 2 then usage(1) end
   local key = args[2]
   table.remove(args, #args)
   return parse_key(key)
end

function run(args)
   local l_args = parse_args(args)
   local opts = { command='compress-alarms', with_path=false, is_config=false }
   args = common.parse_command_line(args, opts)
   local response = common.call_leader(
      args.instance_id, 'compress-alarms',
      { schema = args.schema_name, revision = args.revision,
        resource = l_args.resource, alarm_type_id = l_args.alarm_type_id,
        alarm_type_qualifier = l_args.alarm_type_qualifier,
        print_default = args.print_default, format = args.format })
   common.print_and_exit(response, 'compressed_alarms')
end
