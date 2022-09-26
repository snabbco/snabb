-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local common = require("program.config.common")

function run(args)
   local opts = { command='get', with_path=true, is_config=true }
   args = common.parse_command_line(args, opts)
   if args.error then
      common.print_and_exit(args)
   end
   local response = common.call_leader(
      args.instance_id, 'get-config',
      { schema = args.schema_name, revision = args.revision_date,
        path = args.path, print_default = args.print_default,
        format = args.format })
   common.print_and_exit(response, "config")
end
