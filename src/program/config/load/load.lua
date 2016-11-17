-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local rpc = require("lib.yang.rpc")
local common = require("program.config.common")

function run(args)
   local schema_name, revision_date, instance_id, config =
      common.parse_command_line(args,
                                { command='load', with_config_file=true })
   local caller = rpc.prepare_caller('snabb-config-leader-v1')
   local config_str = common.serialize_config(config, schema_name)
   local data = { schema = schema_name, revision = revision_date,
                  config = config_str }
   local msg, parse = rpc.prepare_call(caller, 'load-config', data)
   local socket = common.open_socket_or_die(instance_id)
   common.send_message(socket, msg)
   local reply = common.recv_message(socket)
   socket:close()
   -- The reply is effectively empty.
   main.exit(0)
end
