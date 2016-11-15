-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local yang = require("lib.yang.yang")
local rpc = require("lib.yang.rpc")
local app = require("core.app")
local shm = require("core.shm")
local app_graph = require("core.config")
local action_queue = require("apps.config.action_queue")
local channel = require("apps.config.channel")

Leader = {
   config = {
      socket_file_name = {default='config-leader-socket'},
      setup_fn = {required=true},
      initial_configuration = {},
      follower_pids = {required=true},
      Hz = {default=100},
   }
}

local function open_socket (file)
   S.signal('pipe', 'ign')
   local socket = assert(S.socket("unix", "stream, nonblock"))
   S.unlink(file) --unlink to avoid EINVAL on bind()
   local sa = S.t.sockaddr_un(file)
   assert(socket:bind(sa))
   assert(socket:listen())
   return socket
end

function Leader:new (conf)
   local ret = setmetatable({}, {__index=Leader})
   ret.socket_file_name = conf.socket_file_name
   if not ret.socket_file_name:match('^/') then
      local instance_dir = shm.root..'/'..tostring(S.getpid())
      ret.socket_file_name = instance_dir..'/'..ret.socket_file_name
   end
   ret.socket = open_socket(ret.socket_file_name)
   ret.peers = {}
   ret.setup_fn = conf.setup_fn
   ret.current_app_graph = app_graph.new()
   ret.period = 1/conf.Hz
   ret.next_time = app.now()
   ret.followers = {}
   for _,pid in ipairs(conf.follower_pids) do
      table.insert(ret.followers, { pid=pid, queue={} })
   end
   ret.rpc_callee = rpc.prepare_callee('snabb-config-leader-v1')
   ret.rpc_handler = rpc.dispatch_handler(ret, 'rpc_')

   ret:reset_configuration(conf.initial_configuration)

   return ret
end

function Leader:reset_configuration (configuration)
   local new_app_graph = self.setup_fn(configuration)
   local actions = app.compute_config_actions(self.current_app_graph,
                                              new_app_graph)
   self:enqueue_config_actions(actions)
   self.current_app_graph = new_app_graph
   self.current_configuration = configuration
end

function Leader:take_follower_message_queue ()
   local actions = self.config_action_queue
   self.config_action_queue = nil
   return actions
end

function Leader:enqueue_config_actions (actions)
   local messages = {}
   for _,action in ipairs(actions) do
      local buf, len = action_queue.encode_action(action)
      table.insert(messages, { buf=buf, len=len })
   end
   for _,follower in ipairs(self.followers) do
      for _,message in ipairs(messages) do
         table.insert(follower.queue, message)
      end
   end
end

function Leader:rpc_get_config (data)
   return { config = "hey!" }
end

function Leader:handle (payload)
   return rpc.handle_calls(self.rpc_callee, payload, self.rpc_handler)
end

function Leader:handle_calls_from_peers()
   local peers = self.peers
   while true do
      local sa = S.t.sockaddr_un()
      local fd, err = self.socket:accept(sa)
      if not fd then
         if err.AGAIN then break end
         assert(nil, err)
      end
      fd:nonblock()
      table.insert(peers, { state='length', len=0, fd=fd })
   end
   local i = 1
   while i <= #peers do
      local peer = peers[i]
      while peer.state == 'length' do
         local ch, err = peer.fd:read(nil, 1)
         if not ch then
            if err.AGAIN then break end
            peer.state = 'error'
            peer.msg = tostring(err)
         elseif ch == '\n' then
            peer.pos = 0
            peer.buf = ffi.new('uint8_t[?]', peer.len)
            peer.state = 'payload'
         elseif tonumber(ch) then
            peer.len = peer.len * 10 + tonumber(ch)
            if peer.len > 1e8 then
               peer.state = 'error'
               peer.msg = 'length too long: '..peer.len
            end
         else
            peer.state = 'error'
            peer.msg = 'unexpected character: '..ch
         end
      end
      while peer.state == 'payload' do
         if peer.pos == peer.len then
            peer.state = 'ready'
            peer.payload = ffi.string(peer.buf, peer.len)
            peer.buf, peer.len = nil, nil
         else
            local count, err = peer.fd:read(peer.buf + peer.pos,
                                            peer.len - peer.pos)
            if not count then
               if err.AGAIN then break end
               peer.state = 'error'
               peer.msg = tostring(err)
            elseif count == 0 then
               peer.state = 'error'
               peer.msg = 'short read'
            else
               peer.pos = peer.pos + count
               assert(peer.pos <= peer.len)
            end
         end
      end
      while peer.state == 'ready' do
         local success, reply = pcall(self.handle, self, peer.payload)
         peer.payload = nil
         if success then
            assert(type(reply) == 'string')
            reply = #reply..'\n'..reply
            peer.state = 'reply'
            peer.buf = ffi.new('uint8_t[?]', #reply, reply)
            peer.pos = 0
            peer.len = #reply
         else
            peer.state = 'error'
            peer.msg = reply
         end
      end
      while peer.state == 'reply' do
         if peer.pos == peer.len then
            peer.state = 'done'
            peer.buf, peer.len = nil, nil
         else
            local count, err = peer.fd:write(peer.buf + peer.pos,
                                             peer.len - peer.pos)
            if not count then
               if err.AGAIN then break end
               peer.state = 'error'
               peer.msg = tostring(err)
            elseif count == 0 then
               peer.state = 'error'
               peer.msg = 'short write'
            else
               peer.pos = peer.pos + count
               assert(peer.pos <= peer.len)
            end
         end
      end
      if peer.state == 'done' then
         peer.fd:close()
         table.remove(peers, i)
      elseif peer.state == 'error' then
         print('error: '..peer.msg)
         peer.fd:close()
         table.remove(peers, i)
      else
         i = i + 1
      end
   end
end

function Leader:send_messages_to_followers()
   for _,follower in ipairs(self.followers) do
      if not follower.channel then
         local name = '/'..tostring(follower.pid)..'/config-follower-channel'
         -- local success, channel = pcall(channel.open, name)
         --if success then follower.channel = channel end
         follower.channel = channel.open(name)
      end
      local channel = follower.channel
      if channel then
         local queue = follower.queue
         follower.queue = {}
         local requeue = false
         for _,msg in ipairs(queue) do
            if not requeue then
               requeue = not channel:put_message(msg.buf, msg.len)
            end
            if requeue then table.insert(follower.queue, msg) end
         end
      end
   end
end

function Leader:pull ()
   if app.now() < self.next_time then return end
   self.next_time = app.now() + self.period
   self:handle_calls_from_peers()
   self:send_messages_to_followers()
end

function Leader:stop ()
   for _,peer in ipairs(self.peers) do peer.fd:close() end
   self.peers = {}
   self.socket:close()
   S.unlink(self.socket_file_name)
end

function selftest ()
   print('selftest: apps.config.leader')
   local graph = app_graph.new()
   local function setup_fn(cfg)
      local graph = app_graph.new()
      local basic_apps = require('apps.basic.basic_apps')
      app_graph.app(graph, "source", basic_apps.Source, {})
      app_graph.app(graph, "sink", basic_apps.Sink, {})
      app_graph.link(graph, "source.foo -> sink.bar")
      return graph
   end
   app_graph.app(graph, "leader", Leader,
                 {setup_fn=setup_fn, follower_pids={S.getpid()}})
   app_graph.app(graph, "follower", require('apps.config.follower').Follower,
                 {})
   engine.configure(graph)
   engine.main({ duration = 0.05, report = {showapps=true,showlinks=true}})
   assert(app.app_table.source)
   assert(app.app_table.sink)
   assert(app.link_table["source.foo -> sink.bar"])
   local link = app.link_table["source.foo -> sink.bar"]
   local counter = require('core.counter')
   assert(counter.read(link.stats.txbytes) > 0)
   assert(counter.read(link.stats.txbytes) == counter.read(link.stats.rxbytes))
   assert(counter.read(link.stats.txdrop) == 0)
   engine.configure(app_graph.new())
   print('selftest: ok')
end
