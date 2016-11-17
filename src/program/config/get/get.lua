-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local rpc = require("lib.yang.rpc")
local common = require("program.config.common")

function run(args)
   local schema_name, revision_date, instance_id, path =
      common.parse_command_line(args, { command='get', with_path=true })
   local caller = rpc.prepare_caller('snabb-config-leader-v1')
   local data = { schema = schema_name, revision = revision_date, path = path }
   local msg, parse = rpc.prepare_call(caller, 'get-config', data)
   local socket = common.open_socket_or_die(instance_id)
   common.send_message(socket, msg)
   local reply = common.recv_message(socket)
   socket:close()
   print(parse(reply).config)
   main.exit(0)
end
