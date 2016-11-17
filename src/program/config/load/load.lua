-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local common = require("program.config.common")

function run(args)
   local schema_name, revision_date, instance_id, config =
      common.parse_command_line(args,
                                { command='load', with_config_file=true })
   local config_str = common.serialize_config(config, schema_name)
   local response = common.call_leader(
      instance_id, 'load-config',
      { schema = schema_name, revision = revision_date,
        config = config_str })
   -- The reply is empty.
   main.exit(0)
end
