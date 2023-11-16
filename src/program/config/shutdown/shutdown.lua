-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local common = require("program.config.common")

function run(args)
   local opts = { command='shutdown', is_config=false }
   args = common.parse_command_line(args, opts)
   if args.error then
      common.print_and_exit(args)
   end
   local response = common.call_leader(
      args.instance_id, 'shutdown', {})
   -- Always returns success with an empty reply
   common.print_and_exit(response)
end
