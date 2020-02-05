-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local yang   = require("lib.yang.yang")
local common = require("program.config.common")

function run(args)
   local opts = { command='test', with_config_file=true, is_config = false}
   local ret, args = common.parse_command_line(args, opts)

   yang.print_config_for_schema_by_name(ret.schema_name, ret.config, io.stdout)
end
