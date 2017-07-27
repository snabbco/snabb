-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local yang = require("lib.yang.yang")
local rpc = require("lib.yang.rpc")
local app = require("core.app")
local shm = require("core.shm")
local app_graph = require("core.config")
local channel = require("apps.config.channel")
local action_codec = require("apps.config.action_codec")

Follower = {
   config = {
      Hz = {default=1000},
   }
}

function Follower:new (conf)
   local ret = setmetatable({}, {__index=Follower})
   ret.period = 1/conf.Hz
   ret.next_time = app.now()
   ret.channel = channel.create('config-follower-channel', 1e6)
   ret.alarms_channel = channel.create('alarms-follower-channel', 1e6)
   ret.pending_actions = {}
   return ret
end

function Follower:commit_pending_actions()
   local to_apply = {}
   local should_flush = false
   for _,action in ipairs(self.pending_actions) do
      local name, args = unpack(action)
      if name == 'call_app_method_with_blob' then
         if #to_apply > 0 then
            app.apply_config_actions(to_apply)
            to_apply = {}
         end
         local callee, method, blob = unpack(args)
         local obj = assert(app.app_table[callee])
         assert(obj[method])(obj, blob)
      else
         if name == 'start_app' or name == 'reconfig_app' then
            should_flush = true
         end
         table.insert(to_apply, action)
      end
   end
   if #to_apply > 0 then app.apply_config_actions(to_apply) end
   self.pending_actions = {}
   if should_flush then require('jit').flush() end
end

function Follower:handle_actions_from_leader()
   local channel = self.channel
   for i=1,4 do
      local buf, len = channel:peek_message()
      if not buf then break end
      local action = action_codec.decode(buf, len)
      if action[1] == 'commit' then
         self:commit_pending_actions()
      else
         table.insert(self.pending_actions, action)
      end
      channel:discard_message(len)
   end
end

function Follower:pull ()
   if app.now() < self.next_time then return end
   self.next_time = app.now() + self.period
   self:handle_actions_from_leader()
end

function selftest ()
   print('selftest: apps.config.follower')
   local c = config.new()
   config.app(c, "follower", Follower, {})
   engine.configure(c)
   engine.main({ duration = 0.0001, report = {showapps=true,showlinks=true}})
   engine.configure(config.new())
   print('selftest: ok')
end
