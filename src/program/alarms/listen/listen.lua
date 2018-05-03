-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local rpc = require("lib.yang.rpc")
local data = require("lib.yang.data")
local path_lib = require("lib.yang.path")
local json_lib = require("lib.ptree.json")
local common = require("program.config.common")

local function open_socket(file)
   S.signal('pipe', 'ign')
   local socket = assert(S.socket("unix", "stream"))
   S.unlink(file)
   local sa = S.t.sockaddr_un(file)
   assert(socket:bind(sa))
   assert(socket:listen())
   return socket
end

local function attach_listener(leader, caller)
   local msg, parse_reply = rpc.prepare_call(
      caller, 'attach-notification-listener', {})
   common.send_message(leader, msg)
   return parse_reply(common.recv_message(leader))
end

function run(args)
   args = common.parse_command_line(args, { command='listen' })
   local caller = rpc.prepare_caller('snabb-config-leader-v1')
   local leader = common.open_socket_or_die(args.instance_id)
   attach_listener(leader, caller)
   
   -- Check if there is a socket path specified, if so use that as method
   -- to communicate, otherwise use stdin and stdout.
   local fd = nil
   if args.socket then
      local sockfd = open_socket(args.socket)
      local addr = S.t.sockaddr_un()
      -- Wait for a connection
      local err
      print("Listening for clients on socket: "..args.socket)
      fd, err = sockfd:accept(addr)
      if fd == nil then
         sockfd:close()
         error(err)
      end
   else
      fd = S.stdin
   end
      
   local client = json_lib.buffered_input(fd)
   local pollfds = S.types.t.pollfds({
         {fd=leader, events="in"},
         {fd=client, events="in"}})
   while true do
      if client:avail() == 0 then
         assert(S.poll(pollfds, -1))
      end
      for _,pfd in ipairs(pollfds) do
         if pfd.fd == leader:getfd() then
            if pfd.ERR or pfd.HUP then
               io.stderr:write('Leader hung up\n')
               main.exit(1)
            elseif pfd.IN then
               print(common.recv_message(leader))
            end
            pfd.revents = 0
         elseif pfd.fd == client:getfd() then
            if pfd.ERR or pfd.HUP or pfd.NVAL then
               io.stderr:write('Client hung up\n')
               main.exit(0)
            end
            if pfd.IN then
               -- The JSON objects sent to us by the client can have
               -- whitespace between them.  Make sure we don't block
               -- expecting a new datum when really it was just the
               -- remote side sending whitespace.  (Calling peek()
               -- causes the buffer to fill, which itself shouldn't
               -- block given the IN flag in the revents.)
               client:peek()
               json_lib.drop_buffered_whitespace(client)
            end
            pfd.revents = 0
         else
            error('unreachable')
         end
      end
   end
end
