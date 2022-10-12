-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local S            = require("syscall")
local engine       = require("core.app")
local app_graph    = require("core.config")
local counter      = require("core.counter")
local histogram    = require('core.histogram')
local lib          = require('core.lib')
local timer        = require('core.timer')
local memory_info  = require("lib.timers.memory_info")
local alarms       = require("lib.yang.alarms")
local channel      = require("lib.ptree.channel")
local action_codec = require("lib.ptree.action_codec")
local ptree_alarms = require("lib.ptree.alarms")

local Worker = {}

local worker_config_spec = {
   duration = {},
   measure_latency = {default=true},
   measure_memory = {default=true},
   no_report = {default=false},
   report = {default={showapps=true,showlinks=true}},
   Hz = {default=1000},
}

function new_worker (conf)
   local conf = lib.parse(conf, worker_config_spec)
   local ret = setmetatable({}, {__index=Worker})
   ret.period = 1/conf.Hz
   ret.duration = conf.duration or 1/0
   ret.no_report = conf.no_report
   ret.channel = channel.create('config-worker-channel', 1e6)
   alarms.install_alarm_handler(ptree_alarms:alarm_handler())
   ret.pending_actions = {}

   ret.breathe = engine.breathe
   if conf.measure_latency then
      local latency = histogram.create('engine/latency.histogram', 1e-6, 1e0)
      ret.breathe = latency:wrap_thunk(ret.breathe, engine.now)
   end
   if conf.measure_memory then
      timer.activate(memory_info.HeapSizeMonitor.new():timer())
   end
   return ret
end

function Worker:shutdown()
   -- This will call stop() on all apps.
   engine.configure(app_graph.new())

   -- Now we can exit.
   S.exit(0)
end

function Worker:commit_pending_actions()
   local to_apply = {}
   local should_flush = false
   for _,action in ipairs(self.pending_actions) do
      local name, args = unpack(action)
      if name == 'call_app_method_with_blob' then
         if #to_apply > 0 then
            engine.apply_config_actions(to_apply)
            to_apply = {}
         end
         local callee, method, blob = unpack(args)
         local obj = assert(engine.app_table[callee])
         assert(obj[method])(obj, blob)
      elseif name == "shutdown" then
         self:shutdown()
      else
         if name == 'start_app' or name == 'reconfig_app' then
            should_flush = true
         end
         table.insert(to_apply, action)
      end
   end
   if #to_apply > 0 then engine.apply_config_actions(to_apply) end
   self.pending_actions = {}
   if should_flush then require('jit').flush() end
end

function Worker:handle_actions_from_manager()
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

function Worker:main ()
   local stop = engine.now() + self.duration
   local next_time = engine.now()

   if not engine.auditlog_enabled then engine.enable_auditlog() end

   engine.enable_tick()

   engine.setvmprofile("engine")
   repeat
      self.breathe()
      if next_time < engine.now() then
         next_time = engine.now() + self.period
         self:handle_actions_from_manager()
         timer.run()
      end
      if not engine.busywait then engine.pace_breathing() end
   until stop < engine.now()
   counter.commit()
   if not self.no_report then engine.report(self.report) end
end

function main (opts)
   return new_worker(opts):main()
end

function selftest ()
   print('selftest: lib.ptree.worker')
   main({duration=0.005})
   print('selftest: ok')
end
