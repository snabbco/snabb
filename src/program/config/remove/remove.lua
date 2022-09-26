-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local common = require("program.config.common")

function run(args)
   args = common.parse_command_line(
      args, { command='remove', with_path=true, is_config=true })
   if args.error then
      common.print_and_exit(args)
   end
   local response = common.call_leader(
      args.instance_id, 'remove-config',
      { schema = args.schema_name, revision = args.revision_date,
        path = args.path })
   -- The reply is empty.
   common.print_and_exit(response)
end
