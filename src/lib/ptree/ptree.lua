-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local C = ffi.C
local app_graph = require("core.config")
local lib = require("core.lib")
local shm = require("core.shm")
local timer = require("core.timer")
local worker = require("core.worker")
local cpuset = require("lib.cpuset")
local rrd = require("lib.rrd")
local scheduling = require("lib.scheduling")
local mem = require("lib.stream.mem")
local socket = require("lib.stream.socket")
local fiber = require("lib.fibers.fiber")
local sched = require("lib.fibers.sched")
local yang = require("lib.yang.yang")
local util = require("lib.yang.util")
local schema = require("lib.yang.schema")
local rpc = require("lib.yang.rpc")
local state = require("lib.yang.state")
local path_mod = require("lib.yang.path")
local path_data = require("lib.yang.path_data")
local action_codec = require("lib.ptree.action_codec")
local ptree_alarms = require("lib.ptree.alarms")
local support = require("lib.ptree.support")
local channel = require("lib.ptree.channel")
local trace = require("lib.ptree.trace")
local alarms = require("lib.yang.alarms")
local json = require("lib.ptree.json")
local queue = require('lib.fibers.queue')
local fiber_sleep = require('lib.fibers.sleep').sleep
local inotify = require("lib.ptree.inotify")
local counter = require("core.counter")
local gauge = require("lib.gauge")
local cond = require("lib.fibers.cond")

local call_with_output_string = mem.call_with_output_string

local Manager = {}

local log_levels = { DEBUG=1, INFO=2, WARN=3 }
local default_log_level = "WARN"
if os.getenv('SNABB_MANAGER_VERBOSE') then default_log_level = "DEBUG" end

local manager_config_spec = {
   name = {},
   rpc_socket_file_name = {default='config-leader-socket'},
   notification_socket_file_name = {default='notifications'},
   setup_fn = {required=true},
   -- Could relax this requirement.
   initial_configuration = {required=true},
   schema_name = {required=true},
   worker_default_scheduling = {default={}},
   default_schema = {},
   log_level = {default=default_log_level},
   rpc_trace_file = {},
   cpuset = {default=cpuset.global_cpuset()},
   Hz = {default=100}
}

local worker_opt_spec = {
   acquire_cpu = {default=true}, -- Needs dedicated CPU core?
   restart_intensity = {default=0}, -- How many restarts are permitted...
   restart_period = {default=0} -- ...within period seconds.
}

local function ensure_absolute(file_name)
   if file_name:match('^/') then
      return file_name
   else
      return shm.root..'/'..tostring(S.getpid())..'/'..file_name
   end
end

function new_manager (conf)
   local conf = lib.parse(conf, manager_config_spec)

   local ret = setmetatable({}, {__index=Manager})
   ret.name = conf.name
   ret.log_level = assert(log_levels[conf.log_level])
   ret.cpuset = conf.cpuset
   ret.rpc_socket_file_name = ensure_absolute(conf.rpc_socket_file_name)
   ret.notification_socket_file_name = ensure_absolute(
      conf.notification_socket_file_name)
   ret.schema_name = conf.schema_name
   ret.default_schema = conf.default_schema or conf.schema_name
   ret.support = support.load_schema_config_support(conf.schema_name)
   ret.peers = {}
   ret.notification_peers = {}
   ret.setup_fn = conf.setup_fn
   ret.period = 1/conf.Hz
   ret.worker_default_scheduling = conf.worker_default_scheduling
   ret.workers = {}
   ret.workers_aux = {}
   ret.worker_app_graphs = {}
   ret.state_change_listeners = {}
   -- name->{aggregated=counter, active=pid->counter, archived=uint64[1]}
   ret.counters = {}
   -- name->{aggregated=gauge, active=pid->gauge}
   ret.gauges = {}

   if conf.rpc_trace_file then
      ret:info("Logging RPCs to %s", conf.rpc_trace_file)
      ret.trace = trace.new({file=conf.rpc_trace_file})

      -- Start trace with initial configuration.
      local p = path_data.printer_for_schema_by_name(
         ret.schema_name, "/", true, "yang", false)
      local str = call_with_output_string(p, conf.initial_configuration)
      ret.trace:record('set-config', {schema=ret.schema_name, config=str})
   end

   ret.rpc_callee = rpc.prepare_callee('snabb-config-leader-v1')
   ret.rpc_handler = rpc.dispatch_handler(ret, 'rpc_', ret.trace)

   ret:start()

   ret:set_initial_configuration(conf.initial_configuration)

   return ret
end

function Manager:log (level, fmt, ...)
   if log_levels[level] < self.log_level then return end
   local prefix = os.date("%F %H:%M:%S")..": "..level..': '
   io.stderr:write(prefix..fmt:format(...)..'\n')
   io.stderr:flush()
end

function Manager:debug(fmt, ...) self:log("DEBUG", fmt, ...) end
function Manager:info(fmt, ...) self:log("INFO", fmt, ...) end
function Manager:warn(fmt, ...) self:log("WARN", fmt, ...) end

function Manager:add_state_change_listener(listener)
   table.insert(self.state_change_listeners, listener)
   for id, worker in pairs(self.workers) do
      listener:worker_starting(id)
      if worker.channel then listener:worker_started(id, worker.pid) end
      if worker.shutting_down then listener:worker_stopping(id) end
   end
end

function Manager:remove_state_change_listener(listener)
   for i, x in ipairs(self.state_change_listeners) do
      if x == listener then
         table.remove(self.state_change_listeners, i)
         return
      end
   end
   error("listener not found")
end

function Manager:state_change_event(event, ...)
   for _,listener in ipairs(self.state_change_listeners) do
      listener[event](listener, ...)
   end
end

function Manager:set_initial_configuration (configuration)
   path_data.consistency_checker_from_schema_by_name(self.schema_name, true)(configuration)
   self.current_configuration = configuration
   self.current_in_place_dependencies = {}

   -- Start the workers and configure them.
   local worker_app_graphs, worker_opts = self.setup_fn(configuration)
   self.workers_aux = self:compute_workers_aux(worker_app_graphs, worker_opts)

   -- Calculate the dependences
   self.current_in_place_dependencies =
      self.support.update_mutable_objects_embedded_in_app_initargs (
	    {}, worker_app_graphs, self.schema_name, 'load',
            '/', self.current_configuration)

   -- Iterate over workers starting the workers and queuing up actions.
   for id, worker_app_graph in pairs(worker_app_graphs) do
      self:start_worker_for_graph(id, worker_app_graph)
   end

   self.worker_app_graphs = worker_app_graphs
end

function Manager:start ()
   if self.name then engine.claim_name(self.name) end
   self:info(("Manager has started (PID %d)"):format(S.getpid()))
   self.cpuset:bind_to_numa_node()
   require('lib.fibers.file').install_poll_io_handler()
   self.sched = fiber.current_scheduler
   fiber.spawn(function () self:accept_rpc_peers() end)
   fiber.spawn(function () self:accept_notification_peers() end)
   fiber.spawn(function () self:notification_poller() end)
   fiber.spawn(function () self:sample_active_stats() end)
end

function Manager:call_with_cleanup(closeable, f, ...)
   local ok, err = pcall(f, ...)
   closeable:close()
   if not ok then self:warn('%s', tostring(err)) end
end

function Manager:accept_rpc_peers ()
   local sock = socket.listen_unix(self.rpc_socket_file_name, {ephemeral=true})
   self:call_with_cleanup(sock, function()
      while true do
         local peer = sock:accept()
         fiber.spawn(function() self:handle_rpc_peer(peer) end)
      end
   end)
end

function Manager:accept_notification_peers ()
   local sock = socket.listen_unix(self.notification_socket_file_name,
                                   {ephemeral=true})
   fiber.spawn(function()
      while true do
         local peer = sock:accept()
         fiber.spawn(function() self:handle_notification_peer(peer) end)
      end
   end)
end

function Manager:handle_rpc_peer(peer)
   self:call_with_cleanup(peer, function()
      while true do
         local prefix = peer:read_line('discard')
         if prefix == nil then return end -- EOF.
         local len = assert(tonumber(prefix), 'not a number: '..prefix)
         assert(tostring(len) == prefix, 'bad number: '..prefix)
         -- FIXME: Use a streaming parse.
         local request = peer:read_chars(len)
         local reply = self:handle(peer, request)
         peer:write_chars(tostring(#reply))
         peer:write_chars('\n')
         peer:write_chars(reply)
         peer:flush_output()
      end
   end)
   if self.listen_peer == peer then self.listen_peer = nil end
end

function Manager:handle_notification_peer(peer)
   local q = queue.new()
   self.notification_peers[q] = true
   function q.close()
      self.notification_peers[q] = nil
      peer:close()
   end
   self:call_with_cleanup(q, function()
      while true do
         json.write_json(peer, q:get())
         peer:write_chars("\n")
         peer:flush_output()
      end
   end)
end

function Manager:run_scheduler()
   self.sched:run(engine.now())
end

function Manager:start_worker(id, sched_opts)
   local code = {
      scheduling.stage(sched_opts),
      "require('lib.ptree.worker').main()"
   }
   return worker.start(id, table.concat(code, "\n"))
end

function Manager:stop_worker(id)
   self:info('Asking worker %s to shut down.', id)
   local stop_actions = {{'shutdown', {}}, {'commit', {}}}
   self:state_change_event('worker_stopping', id)
   self:enqueue_config_actions_for_worker(id, stop_actions)
   self:send_messages_to_workers()
   self.workers[id].shutting_down = true
   self.workers[id].cancel:signal()
end

function Manager:remove_stale_workers()
   local stale = {}
   for id, worker in pairs(self.workers) do
      if worker.shutting_down then
	 if S.waitpid(worker.pid, S.c.W["NOHANG"]) ~= 0 then
	    stale[#stale + 1] = id
	 end
      end
   end
   for _, id in ipairs(stale) do
      self:state_change_event('worker_stopped', id)
      if self.workers[id].scheduling.cpu then
	 self.cpuset:release(self.workers[id].scheduling.cpu)
      end
      self.workers[id] = nil

   end
end

function Manager:compute_workers_aux (worker_app_graphs, worker_opts)
   worker_opts = worker_opts or {}
   local workers_aux = {}
   for id in pairs(worker_app_graphs) do
      local worker_opt = lib.parse(worker_opts[id] or {}, worker_opt_spec)
      local worker_aux = {
         acquire_cpu = worker_opt.acquire_cpu,
         restart = {
            period = worker_opt.restart_period,
            intensity = worker_opt.restart_intensity,
            count = 0,
            previous = false
         }
      }
      workers_aux[id] = worker_aux
   end
   return workers_aux
end

function Manager:can_restart_worker(id)
   local restart = self.workers_aux[id].restart
   local now = engine.now()
   local expired = 0
   if restart.previous then
      local elapsed = now - restart.previous
      expired = (elapsed / restart.period) * restart.intensity
   end
   restart.count = math.max(0, restart.count - expired) + 1
   restart.previous = now
   self:info('Restart intensity for worker %s is at: %.1f/%.1f',
             id, restart.count, restart.intensity)
   return restart.count <= restart.intensity
end

function Manager:restart_crashed_workers()
   for id, proc in pairs(worker.status()) do
      local worker = self.workers[id]
      if worker and not worker.shutting_down then
         if not proc.alive then
            self:warn('Worker %s (pid %d) crashed with status %d!',
                        id, proc.pid, proc.status)
            self:state_change_event('worker_stopped', id)
            if self.workers[id].scheduling.cpu then
               self.cpuset:release(self.workers[id].scheduling.cpu)
            end
            self.workers[id] = nil
            if self:can_restart_worker(id) then
               self:info('Restarting worker %s.', id)
               self:start_worker_for_graph(id, self.worker_app_graphs[id])
            else
               self:warn('Too many worker crashes, exiting!')
               self:stop()
               os.exit(1)
            end
         end
      end
   end
end

function Manager:acquire_cpu_for_worker(id, app_graph)
   local pci_addresses = {}
   -- Grovel through app initargs for keys named "pciaddr".  Hacky!
   for name, init in pairs(app_graph.apps) do
      if type(init.arg) == 'table' then
         for k, v in pairs(init.arg) do
            if (k == 'pciaddr' or k == 'pciaddress') and not lib.is_iface(v) then
               table.insert(pci_addresses, v)
            end
         end
      end
   end
   return self.cpuset:acquire_for_pci_addresses(pci_addresses, id)
end

function Manager:compute_scheduling_for_worker(id, app_graph)
   local ret = {}
   for k, v in pairs(self.worker_default_scheduling) do ret[k] = v end
   if self.workers_aux[id].acquire_cpu then
      ret.cpu = self:acquire_cpu_for_worker(id, app_graph)
   end
   return ret
end

local function has_suffix(a, b) return a:sub(-#b) == b end
local function has_prefix(a, b) return a:sub(1,#b) == b end
local function strip_prefix(a, b)
   assert(has_prefix(a, b))
   return a:sub(#b+1)
end
local function strip_suffix(a, b)
   assert(has_suffix(a, b))
   return a:sub(1,-(#b+1))
end

function Manager:make_rrd(counter_name, typ)
   typ = typ or 'counter'
   local name = strip_suffix(counter_name, "."..typ)..'.rrd'
   return rrd.create_shm(name, {
      sources={{name='value', type=typ}},
      -- NOTE: The default heartbeat interval is 1s, so relax
      -- base_interval to 2s as we're only polling every 1s (and we'll
      -- be slightly late).  Also note that these settings correspond to
      -- about 100 KB of data for each counter.  On a box with 1000
      -- counters, that's 100 MB, which seems reasonable for such a
      -- facility.
      archives={{cf='average', duration='2h', interval='2s'},
                {cf='average', duration='24h', interval='30s'},
                {cf='max', duration='24h', interval='30s'},
                {cf='average', duration='7d', interval='5m'},
                {cf='max', duration='7d', interval='5m'}},
      base_interval='2s' })
end

local blacklisted_counters = lib.set('macaddr', 'mtu', 'promisc', 'speed', 'status', 'type')
local function blacklisted (name)
   return blacklisted_counters[strip_suffix(lib.basename(name), '.counter')]
end

function Manager:monitor_worker_stats(id)
   local worker = self.workers[id]
   if not worker then return end -- Worker was removed before monitor started.
   local pid, cancel = worker.pid, worker.cancel:wait_operation()
   local dir = shm.root..'/'..pid
   local events = inotify.recursive_directory_inventory_events(dir, cancel)
   for ev in events.get, events do
      if has_prefix(ev.name, dir..'/') then
         local name = strip_prefix(ev.name, dir..'/')
         local qualified_name = '/'..pid..'/'..name
         if has_suffix(ev.name, '.counter') then
            local counters = self.counters[name]
            if blacklisted(name) then
            -- Pass.
            elseif ev.kind == 'creat' then
               if not counters then
                  counters = { aggregated=counter.create(name), active={},
                               rrd={}, aggregated_rrd=self:make_rrd(name),
                               archived=ffi.new('uint64_t[1]') }
                  self.counters[name] = counters
               end
               counters.active[pid] = counter.open(qualified_name)
               counters.rrd[pid] = self:make_rrd(qualified_name)
            elseif ev.kind == 'rm' then
               local val = counter.read(assert(counters.active[pid]))
               counters.active[pid] = nil
               counters.rrd[pid] = nil
               counters.archived[0] = counters.archived[0] + val
               counter.delete(qualified_name)
               S.unlink(strip_suffix(qualified_name, ".counter")..".rrd")
               local last_in_set = true
               for _ in pairs(counters.active) do
                  last_in_set = false
                  break
               end
               if last_in_set then
                  self:cleanup_aggregated_stats(name, 'counter')
               end
            end
         elseif has_suffix(ev.name, '.gauge') then
            local gauges = self.gauges[name]
            if ev.kind == 'creat' then
               if not gauges then
                  gauges = { aggregated=gauge.create(name), active={},
                             rrd={}, aggregated_rrd=self:make_rrd(name, 'gauge') }
                  self.gauges[name] = gauges
               end
               gauges.active[pid] = gauge.open(qualified_name)
               gauges.rrd[pid] = self:make_rrd(qualified_name, 'gauge')
            elseif ev.kind == 'rm' then
               shm.unmap(gauges.active[pid])
               gauges.active[pid] = nil
               gauges.rrd[pid] = nil
               S.unlink(strip_suffix(qualified_name, ".gauge")..".rrd")
               local last_in_set = true
               for _ in pairs(gauges.active) do
                  last_in_set = false
                  break
               end
               if last_in_set then
                  self:cleanup_aggregated_stats(name, 'gauge')
               end
            end
         end
      end
   end
end

function Manager:sample_active_stats()
   while true do
      local now = rrd.now()
      for name, counters in pairs(self.counters) do
         local sum = counters.archived[0]
         for pid, active in pairs(counters.active) do
            local v = counter.read(active)
            counters.rrd[pid]:add({value=v}, now)
            sum = sum + v
         end
         counters.aggregated_rrd:add({value=sum}, now)
         counter.set(counters.aggregated, sum)
      end
      counter.commit()
      for name, gauges in pairs(self.gauges) do
         local sum = 0
         for pid, active in pairs(gauges.active) do
            local v = gauge.read(active)
            gauges.rrd[pid]:add({value=v}, now)
            sum = sum + v
         end
         gauges.aggregated_rrd:add({value=sum}, now)
         gauge.set(gauges.aggregated, sum)
      end
      fiber_sleep(1)
   end
end

function Manager:cleanup_aggregated_stats(name, typ)
   shm.unlink(name)
   shm.unlink(strip_suffix(name, "."..typ)..".rrd")
   self:cleanup_parent_directories(name)
end

function Manager:cleanup_parent_directories(name)
   local parent = name:match("(.*)/[^/]+$")
   if not parent then return end
   for _ in pairs(shm.children(parent)) do return end
   shm.unlink(parent)
   self:cleanup_parent_directories(parent)
end

function Manager:start_worker_for_graph(id, graph)
   local scheduling = self:compute_scheduling_for_worker(id, graph)
   self:info('Starting worker %s.', id)
   self.workers[id] = { scheduling=scheduling,
                        pid=self:start_worker(id, scheduling),
                        queue={}, graph=graph,
                        cancel=cond.new() }
   self:state_change_event('worker_starting', id)
   self:debug('Worker %s has PID %s.', id, self.workers[id].pid)
   local actions = self.support.compute_config_actions(
      app_graph.new(), self.workers[id].graph, {}, 'load')
   self:enqueue_config_actions_for_worker(id, actions)
   fiber.spawn(function () self:monitor_worker_stats(id) end)

   return self.workers[id]
end

function Manager:take_worker_message_queue ()
   local actions = self.config_action_queue
   self.config_action_queue = nil
   return actions
end

function Manager:enqueue_config_actions_for_worker(id, actions)
   for _,action in ipairs(actions) do
      self:debug('encode %s for worker %s', action[1], id)
      local buf, len = action_codec.encode(action)
      table.insert(self.workers[id].queue, { buf=buf, len=len })
   end
end

function Manager:enqueue_config_actions (actions)
   for id,_ in pairs(self.workers) do
      self.enqueue_config_actions_for_worker(id, actions)
   end
end

function Manager:rpc_describe (args)
   local alternate_schemas = {}
   for schema_name, translator in pairs(self.support.translators) do
      table.insert(alternate_schemas, schema_name)
   end
   return { native_schema = self.schema_name,
	    default_schema = self.default_schema,
            alternate_schema = alternate_schemas,
            capability = schema.get_default_capabilities() }
end

function Manager:rpc_get_schema (args)
   local function getter()
      return { source = schema.load_schema_source_by_name(
                  args.schema, args.revision) }
   end
   local success, response = pcall(getter)
   if success then return response else return {status=1, error=response} end
end

function Manager:rpc_get_config (args)
   local function getter()
      if args.schema ~= self.schema_name then
         return self:foreign_rpc_get_config(
            args.schema, args.path, args.format, args.print_default)
      end
      local printer = path_data.printer_for_schema_by_name(
         args.schema, args.path, true, args.format, args.print_default)
      local str = call_with_output_string(printer, self.current_configuration)
      return { config = str }
   end
   local success, response = pcall(getter)
   if success then return response else return {status=1, error=response} end
end

function Manager:rpc_set_alarm_operator_state (args)
   local function getter()
      if args.schema ~= self.schema_name then
         error(("Set-operator-state operation not supported in '%s' schema"):format(args.schema))
      end
      local key = {resource=args.resource, alarm_type_id=args.alarm_type_id,
                   alarm_type_qualifier=args.alarm_type_qualifier}
      local params = {state=args.state, text=args.text}
      return { success = alarms.set_operator_state(key, params) }
   end
   local success, response = pcall(getter)
   if success then return response else return {status=1, error=response} end
end

function Manager:rpc_purge_alarms (args)
   local function purge()
      if args.schema ~= self.schema_name then
         error(("Purge-alarms operation not supported in '%s' schema"):format(args.schema))
      end
      return { purged_alarms = alarms.purge_alarms(args) }
   end
   local success, response = pcall(purge)
   if success then return response else return {status=1, error=response} end
end

function Manager:rpc_compress_alarms (args)
   local function compress()
      if args.schema ~= self.schema_name then
         error(("Compress-alarms operation not supported in '%s' schema"):format(args.schema))
      end
      return { compressed_alarms = alarms.compress_alarms(args) }
   end
   local success, response = pcall(compress)
   if success then return response else return {status=1, error=response} end
end

function Manager:notify_pre_update (config, verb, path, ...)
   for _,translator in pairs(self.support.translators) do
      translator.pre_update(config, verb, path, ...)
   end
end

function Manager:update_configuration (update_fn, verb, path, ...)
   self:notify_pre_update(self.current_configuration, verb, path, ...)
   local to_restart =
      self.support.compute_apps_to_restart_after_configuration_update (
         self.schema_name, self.current_configuration, verb, path,
         self.current_in_place_dependencies, ...)
   local new_config = update_fn(self.current_configuration, ...)
   local new_graphs, new_opts = self.setup_fn(new_config, ...)
   self.workers_aux = self:compute_workers_aux(new_graphs, new_opts)
   for id, graph in pairs(new_graphs) do
      if self.workers[id] == nil then
         self:start_worker_for_graph(id, graph)
      end
   end

   for id, worker in pairs(self.workers) do
      if new_graphs[id] == nil then
         self:stop_worker(id)
      else
         local actions = self.support.compute_config_actions(
            worker.graph, new_graphs[id], to_restart, verb, path, ...)
         self:enqueue_config_actions_for_worker(id, actions)
	      worker.graph = new_graphs[id]
      end
   end
   self.current_configuration = new_config
   self.current_in_place_dependencies =
      self.support.update_mutable_objects_embedded_in_app_initargs (
         self.current_in_place_dependencies, new_graphs, self.schema_name,
         verb, path, ...)
   self.worker_app_graphs = new_graphs
end

function Manager:handle_rpc_update_config (args, verb, compute_update_fn)
   local path = path_mod.normalize_path(args.path)
   local parser = path_data.parser_for_schema_by_name(args.schema, path)
   self:update_configuration(compute_update_fn(args.schema, path),
                             verb, path,
                             parser(mem.open_input_string(args.config)))
   return {}
end

function Manager:get_native_state ()
   local states = {}
   local state_reader = self.support.compute_state_reader(self.schema_name)
   for _, worker in pairs(self.workers) do
      local worker_config = self.support.configuration_for_worker(
         worker, self.current_configuration)
      table.insert(states, state_reader(worker.pid, worker_config))
   end
   return self.support.process_states(states)
end

function Manager:get_translator (schema_name)
   local translator = self.support.translators[schema_name]
   if translator then return translator end
   error('unsupported schema: '..schema_name)
end
function Manager:apply_translated_rpc_updates (updates)
   for _,update in ipairs(updates) do
      local verb, args = unpack(update)
      local method = assert(self['rpc_'..verb..'_config'])
      method(self, args)
   end
   return {}
end
function Manager:foreign_rpc_get_config (schema_name, path, format,
                                        print_default)
   path = path_mod.normalize_path(path)
   local translate = self:get_translator(schema_name)
   local foreign_config = translate.get_config(self.current_configuration)
   local printer = path_data.printer_for_schema_by_name(
      schema_name, path, true, format, print_default)
   return { config = call_with_output_string(printer, foreign_config) }
end
function Manager:foreign_rpc_get_state (schema_name, path, format,
                                       print_default)
   path = path_mod.normalize_path(path)
   local translate = self:get_translator(schema_name)
   local foreign_state = translate.get_state(self:get_native_state(),
                                             self.current_configuration)
   local printer = path_data.printer_for_schema_by_name(
      schema_name, path, false, format, print_default)
   return { state = call_with_output_string(printer, foreign_state) }
end
function Manager:foreign_rpc_set_config (schema_name, path, config_str)
   path = path_mod.normalize_path(path)
   local translate = self:get_translator(schema_name)
   local parser = path_data.parser_for_schema_by_name(schema_name, path)
   local updates = translate.set_config(
      self.current_configuration, path,
      parser(mem.open_input_string(config_str)))
   return self:apply_translated_rpc_updates(updates)
end
function Manager:foreign_rpc_add_config (schema_name, path, config_str)
   path = path_mod.normalize_path(path)
   local translate = self:get_translator(schema_name)
   local parser = path_data.parser_for_schema_by_name(schema_name, path)
   local updates = translate.add_config(
      self.current_configuration, path,
      parser(mem.open_input_string(config_str)))
   return self:apply_translated_rpc_updates(updates)
end
function Manager:foreign_rpc_remove_config (schema_name, path)
   path = path_mod.normalize_path(path)
   local translate = self:get_translator(schema_name)
   local updates = translate.remove_config(self.current_configuration, path)
   return self:apply_translated_rpc_updates(updates)
end

function Manager:rpc_set_config (args)
   local function setter()
      if self.listen_peer ~= nil and self.listen_peer ~= self.rpc_peer then
         error('Attempt to modify configuration while listener attached')
      end
      if args.schema ~= self.schema_name then
         return self:foreign_rpc_set_config(args.schema, args.path, args.config)
      end
      return self:handle_rpc_update_config(
         args, 'set', path_data.setter_for_schema_by_name)
   end
   local success, response = pcall(setter)
   if success then return response else return {status=1, error=response} end
end

function Manager:rpc_add_config (args)
   local function adder()
      if self.listen_peer ~= nil and self.listen_peer ~= self.rpc_peer then
         error('Attempt to modify configuration while listener attached')
      end
      if args.schema ~= self.schema_name then
         return self:foreign_rpc_add_config(args.schema, args.path, args.config)
      end
      return self:handle_rpc_update_config(
         args, 'add', path_data.adder_for_schema_by_name)
   end
   local success, response = pcall(adder)
   if success then return response else return {status=1, error=response} end
end

function Manager:rpc_remove_config (args)
   local function remover()
      if self.listen_peer ~= nil and self.listen_peer ~= self.rpc_peer then
         error('Attempt to modify configuration while listener attached')
      end
      if args.schema ~= self.schema_name then
         return self:foreign_rpc_remove_config(args.schema, args.path)
      end
      local path = path_mod.normalize_path(args.path)
      self:update_configuration(
         path_data.remover_for_schema_by_name(args.schema, path), 'remove', path)
      return {}
   end
   local success, response = pcall(remover)
   if success then return response else return {status=1, error=response} end
end

function Manager:rpc_attach_listener (args)
   local function attacher()
      if self.listen_peer ~= nil then error('Listener already attached') end
      self.listen_peer = self.rpc_peer
      return {}
   end
   local success, response = pcall(attacher)
   if success then return response else return {status=1, error=response} end
end

function Manager:rpc_get_state (args)
   local function getter()
      if args.schema ~= self.schema_name then
         return self:foreign_rpc_get_state(args.schema, args.path,
                                           args.format, args.print_default)
      end
      local state = self:get_native_state()
      local printer = path_data.printer_for_schema_by_name(
         self.schema_name, args.path, false, args.format, args.print_default)
      return { state = call_with_output_string(printer, state) }
   end
   local success, response = pcall(getter)
   if success then return response else return {status=1, error=response} end
end

function Manager:rpc_get_alarms_state (args)
   local function getter()
      assert(args.schema == "ietf-alarms")
      local printer = path_data.printer_for_schema_by_name(
         args.schema, args.path, false, args.format, args.print_default)
      local state = {
         alarms = alarms.get_state()
      }
      return { state = call_with_output_string(printer, state) }
   end
   local success, response = pcall(getter)
   if success then return response else return {status=1, error=response} end
end

function Manager:handle (peer, payload)
   -- FIXME: Stream call and response instead of building strings.
   self.rpc_peer = peer
   local ret = mem.call_with_output_string(
      rpc.handle_calls, self.rpc_callee, mem.open_input_string(payload),
      self.rpc_handler)
   self.rpc_peer = nil
   return ret
end

-- Spawn in a fiber.
function Manager:notification_poller ()
   while true do
      local notifications = alarms.notifications()
      if #notifications == 0 then
         fiber_sleep(1/50) -- poll at 50 Hz.
      else
         for q,_ in pairs(self.notification_peers) do
            for _,notification in ipairs(notifications) do
               q:put(notification)
            end
         end
      end
   end
end

function Manager:send_messages_to_workers()
   for id,worker in pairs(self.workers) do
      if not worker.channel then
         local name = '/'..tostring(worker.pid)..'/config-worker-channel'
         local success, channel = pcall(channel.open, name)
         if success then
            worker.channel = channel
            self:state_change_event('worker_started', id, worker.pid)
            self:info("Worker %s has started (PID %s).", id, worker.pid)
         end
      end
      local channel = worker.channel
      if channel then
         local queue = worker.queue
         worker.queue = {}
         local requeue = false
         for _,msg in ipairs(queue) do
            if not requeue then
               requeue = not channel:put_message(msg.buf, msg.len)
            end
            if requeue then table.insert(worker.queue, msg) end
         end
      end
   end
end

function Manager:receive_alarms_from_workers ()
   for _,worker in pairs(self.workers) do
      self:receive_alarms_from_worker(worker)
   end
end

function Manager:receive_alarms_from_worker (worker)
   if not worker.alarms_channel then
      local name = '/'..tostring(worker.pid)..'/alarms-worker-channel'
      local success, channel = pcall(channel.open, name)
      if not success then return end
      worker.alarms_channel = channel
   end
   local channel = worker.alarms_channel
   while true do
      local buf, len = channel:peek_message()
      if not buf then break end
      local name, key, args = ptree_alarms.decode(buf, len)
      local ok, err = pcall(self.handle_alarm, self, worker, name, key, args)
      if not ok then self:warn('failed to handle alarm op %s', name) end
      channel:discard_message(len)
   end
end

function Manager:handle_alarm (worker, name, key, args)
   alarms[name](key, args)
end

function Manager:stop ()
   -- Call shutdown for 0.1s or until it returns true (all tasks cancelled).
   local now = C.get_monotonic_time()
   local threshold = now + 0.1
   while now < threshold do
      if self.sched:shutdown() then break end
   end
   if now >= threshold then
      io.stderr:write("Warning: there are still tasks pending\n")
   end

   require('lib.fibers.file').uninstall_poll_io_handler()

   for id, worker in pairs(self.workers) do
      if not worker.shutting_down then self:stop_worker(id) end
   end
   -- Wait 250ms for workers to shut down nicely, polling every 5ms.
   local start = C.get_monotonic_time()
   local wait = 0.25
   while C.get_monotonic_time() < start + wait do
      self:remove_stale_workers()
      if not next(self.workers) then break end
      C.usleep(5000)
   end
   -- If that didn't work, send SIGKILL and wait indefinitely.
   for id, worker in pairs(self.workers) do
      self:warn('Forcing worker %s to shut down.', id)
      S.kill(worker.pid, "KILL")
   end
   while next(self.workers) do
      self:remove_stale_workers()
      C.usleep(5000)
   end
   if self.name then engine.unclaim_name(self.name) end
   self:info('Shutdown complete.')
end

function Manager:main (duration)
   local now = C.get_monotonic_time()
   local stop = now + (duration or 1/0)
   while now < stop do
      next_time = now + self.period
      if timer.ticks then timer.run_to_time(now * 1e9) end
      self:remove_stale_workers()
      self:restart_crashed_workers()
      self:run_scheduler()
      self:send_messages_to_workers()
      self:receive_alarms_from_workers()
      now = C.get_monotonic_time()
      if now < next_time then
         C.usleep(math.floor((next_time - now) * 1e6))
         now = C.get_monotonic_time()
      end
   end
end

function main (opts, duration)
   local m = new_manager(opts)
   m:main(duration)
   m:stop()
end

function selftest ()
   print('selftest: lib.ptree.ptree')
   local function setup_fn(cfg)
      local graph = app_graph.new()
      local basic_apps = require('apps.basic.basic_apps')
      app_graph.app(graph, "source", basic_apps.Source, {})
      app_graph.app(graph, "sink", basic_apps.Sink, {})
      app_graph.link(graph, "source.foo -> sink.bar")
      return {graph}
   end
   local m = new_manager({setup_fn=setup_fn,
                          -- Use a schema with no data nodes, just for
                          -- testing.
                          schema_name='ietf-inet-types',
                          initial_configuration={},
                          log_level="DEBUG"})
   local l = {log={}}
   function l:worker_starting(...) table.insert(self.log,{'starting',...}) end
   function l:worker_started(...)  table.insert(self.log,{'started',...})  end
   function l:worker_stopping(...) table.insert(self.log,{'stopping',...}) end
   function l:worker_stopped(...)  table.insert(self.log,{'stopped',...})  end
   m:add_state_change_listener(l)
   assert(m.workers[1])
   local pid = m.workers[1].pid
   assert(m.workers[1].graph.links)
   assert(m.workers[1].graph.links["source.foo -> sink.bar"])
   -- Worker will be started once main loop starts to run.
   assert(not m.workers[1].channel)
   -- Wait for worker to start.
   while not m.workers[1].channel do m:main(0.005) end
   m:stop()
   assert(m.workers[1] == nil)
   assert(lib.equal(l.log,
                    { {'starting', 1}, {'started', 1, pid}, {'stopping', 1},
                      {'stopped', 1} }))
   print('selftest: ok')
end
