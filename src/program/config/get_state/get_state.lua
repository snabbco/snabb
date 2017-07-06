-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local common = require("program.config.common")

function run(args)
	args = common.parse_command_line(args, {command='get-state', with_path=true})
	local response = common.call_leader(
   	args.instance_id, 'get-state',
      { schema = args.schema_name, revision = args.revision_date,
        path = args.path, print_default = args.print_default,
        format = args.format })
	common.print_and_exit(response, "state")
end
