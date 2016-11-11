-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local yang = require("lib.yang.yang")

Leader = {
   config = {
      socket_file_name = {required=true},
      -- worker_app_name = {required=true}
   }
}

function Leader:new (conf)
   -- open socket
   self.conf = conf
   local socket = assert(S.socket("unix", "stream, nonblock"))
   S.unlink(conf.socket_file_name) --unlink to avoid EINVAL on bind()
   local sa = S.t.sockaddr_un(conf.socket_file_name)
   assert(socket:bind(sa))
   assert(socket:listen())
   return setmetatable({socket=socket, peers={}}, {__index=Leader})
end

function Leader:pull ()
   local peers = self.peers
   while true do
      local sa = S.t.sockaddr_un()
      local fd, err = self.socket:accept(sa)
      if not fd then
         if err.AGAIN then break end
         assert(nil, err)
      end
      table.insert(peers, { state='length', read=0, accum='', fd=fd })
   end
   local i = 1
   while i <= #peers do
      local peer = peers[i]
      if peer.state == 'length' then
         ---
      end
      if peer.state == 'payload' then
         ---
      end
      if peer.state == 'ready' then
         ---
      end
      if peer.state == 'reply' then
         ---
      end
      if peer.state == 'done' then
         peer.fd:close()
         table.remove(peers, i)
      else
         i = i + 1
      end
   end
end

function Leader:stop ()
   for _,peer in ipairs(self.peers) do peer.fd:close() end
   self.peers = {}
   self.socket:close()
   S.unlink(self.conf.socket_file_name)
end

function selftest ()
   print('selftest: apps.config.leader')
   local pcap = require("apps.pcap.pcap")
   local Match = require("apps.test.match").Match
   local c = config.new()
   local tmp = os.tmpname()
   config.app(c, "leader", Leader, {socket_file_name=tmp})
   engine.configure(c)
   engine.main({ duration = 0.0001, report = {showapps=true,showlinks=true}})
   os.remove(tmp)
   print('selftest: ok')
end
