-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local common = require("program.config.common")

function run(args)
   local schema_name, revision_date, instance_id, path =
      common.parse_command_line(args, { command='load', with_path=true })
   local response = common.call_leader(
      instance_id, 'get-config',
      { schema = schema_name, revision = revision_date,
        path = path })
   print(response.config)
   main.exit(0)
end
