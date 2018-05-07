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
local cltable = require("lib.cltable")
local cpuset = require("lib.cpuset")
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
local alarm_codec = require("lib.ptree.alarm_codec")
local support = require("lib.ptree.support")
local channel = require("lib.ptree.channel")
local trace = require("lib.ptree.trace")
local alarms = require("lib.yang.alarms")
local json_lib = require("lib.ptree.json")

local call_with_output_string = mem.call_with_output_string

local Manager = {}

local log_levels = { DEBUG=1, INFO=2, WARN=3 }
local default_log_level = "WARN"
if os.getenv('SNABB_MANAGER_VERBOSE') then default_log_level = "DEBUG" end

local manager_config_spec = {
   name = {},
   socket_file_name = {default='config-leader-socket'},
   setup_fn = {required=true},
   -- Could relax this requirement.
   initial_configuration = {required=true},
   schema_name = {required=true},
   worker_default_scheduling = {default={}},
   default_schema = {},
   log_level = {default=default_log_level},
   rpc_trace_file = {},
   cpuset = {default=cpuset.global_cpuset()},
   Hz = {default=100},
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

function new_manager (conf)
   local conf = lib.parse(conf, manager_config_spec)

   local ret = setmetatable({}, {__index=Manager})
   ret.name = conf.name
   ret.log_level = assert(log_levels[conf.log_level])
   ret.cpuset = conf.cpuset
   ret.socket_file_name = conf.socket_file_name
   if not ret.socket_file_name:match('^/') then
      local instance_dir = shm.root..'/'..tostring(S.getpid())
      ret.socket_file_name = instance_dir..'/'..ret.socket_file_name
   end
   ret.schema_name = conf.schema_name
   ret.default_schema = conf.default_schema or conf.schema_name
   ret.support = support.load_schema_config_support(conf.schema_name)
   ret.peers = {}
   ret.notification_peers = {}
   ret.setup_fn = conf.setup_fn
   ret.period = 1/conf.Hz
   ret.worker_default_scheduling = conf.worker_default_scheduling
   ret.workers = {}
   ret.state_change_listeners = {}

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

   ret:set_initial_configuration(conf.initial_configuration)

   ret:start()

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
   self.current_configuration = configuration
   self.current_in_place_dependencies = {}

   -- Start the workers and configure them.
   local worker_app_graphs = self.setup_fn(configuration)

   -- Calculate the dependences
   self.current_in_place_dependencies =
      self.support.update_mutable_objects_embedded_in_app_initargs (
	    {}, worker_app_graphs, self.schema_name, 'load',
            '/', self.current_configuration)

   -- Iterate over workers starting the workers and queuing up actions.
   for id, worker_app_graph in pairs(worker_app_graphs) do
      self:start_worker_for_graph(id, worker_app_graph)
   end
end

function Manager:start ()
   if self.name then engine.claim_name(self.name) end
   self.cpuset:bind_to_numa_node()
   require('lib.fibers.file').install_poll_io_handler()
   self.sched = fiber.current_scheduler
   local sockname = self.socket_file_name
   local sock = socket.listen_unix(sockname)
   local parent_close = sock.close
   function sock:close()
      parent_close(sock)
      S.unlink(sockname)
   end
   fiber.spawn(function () self:accept_peers(sock) end)
end

function Manager:call_with_cleanup(closeable, f, ...)
   local ok, err = pcall(f, ...)
   closeable:close()
   if not ok then self:warn('%s', tostring(err)) end
end

function Manager:accept_peers (sock)
   self:call_with_cleanup(sock, function()
      while true do
         local peer = sock:accept()
         fiber.spawn(function() self:handle_peer(peer) end)
      end
   end)
end

function Manager:handle_peer(peer)
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

function Manager:run_scheduler()
   self.sched:run(engine.now())
end

function Manager:start_worker(sched_opts)
   local code = {
      scheduling.stage(sched_opts),
      "require('lib.ptree.worker').main()"
   }
   return worker.start("worker", table.concat(code, "\n"))
end

function Manager:stop_worker(id)
   self:info('Asking worker %s to shut down.', id)
   local stop_actions = {{'shutdown', {}}, {'commit', {}}}
   self:state_change_event('worker_stopping', id)
   self:enqueue_config_actions_for_worker(id, stop_actions)
   self:send_messages_to_workers()
   self.workers[id].shutting_down = true
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

function Manager:acquire_cpu_for_worker(id, app_graph)
   local pci_addresses = {}
   -- Grovel through app initargs for keys named "pciaddr".  Hacky!
   for name, init in pairs(app_graph.apps) do
      if type(init.arg) == 'table' then
         for k, v in pairs(init.arg) do
            if k == 'pciaddr' then table.insert(pci_addresses, v) end
         end
      end
   end
   return self.cpuset:acquire_for_pci_addresses(pci_addresses)
end

function Manager:compute_scheduling_for_worker(id, app_graph)
   local ret = {}
   for k, v in pairs(self.worker_default_scheduling) do ret[k] = v end
   ret.cpu = self:acquire_cpu_for_worker(id, app_graph)
   return ret
end

function Manager:start_worker_for_graph(id, graph)
   local scheduling = self:compute_scheduling_for_worker(id, graph)
   self:info('Starting worker %s.', id)
   self.workers[id] = { scheduling=scheduling,
                        pid=self:start_worker(scheduling),
                        queue={}, graph=graph }
   self:state_change_event('worker_starting', id)
   self:debug('Worker %s has PID %s.', id, self.workers[id].pid)
   local actions = self.support.compute_config_actions(
      app_graph.new(), self.workers[id].graph, {}, 'load')
   self:enqueue_config_actions_for_worker(id, actions)
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
   local new_graphs = self.setup_fn(new_config, ...)
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
         self.current_in_place_dependencies, new_graphs, verb, path, ...)
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
   local foreign_state = translate.get_state(self:get_native_state())
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

function Manager:rpc_attach_notification_listener ()
   local i, peers = 1, self.peers
   while i <= #peers do
      if peers[i] == self.rpc_peer then break end
      i = i + 1
   end
   if i <= #peers then
      table.insert(self.notification_peers, self.rpc_peer)
      table.remove(self.peers, i)
   end
   return {}
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

function Manager:push_notifications_to_peers()
   local notifications = alarms.notifications()
   if #notifications == 0 then return end
   local function head (queue)
      local msg = assert(queue[1])
      local len = #msg
      return ffi.cast('uint8_t*', msg), len
   end
   local function tojson (output, str)
      json_lib.write_json_object(output, str)
      local msg = output:flush()
      return tostring(#msg)..'\n'..msg
   end
   -- Enqueue notifications into each peer queue.
   local peers = self.notification_peers
   for _,peer in ipairs(peers) do
      local output = json_lib.buffered_output()
      peer.queue = peer.queue or {}
      for _,each in ipairs(notifications) do
         table.insert(peer.queue, tojson(output, each))
      end
   end
   -- Iterate peers and send enqueued messages.
   for i,peer in ipairs(peers) do
      local queue = peer.queue
      while #queue > 0 do
         local buf, len = head(peer.queue)
         peer.pos = peer.pos or 0
         local count, err = peer.fd:write(buf + peer.pos,
                                          len - peer.pos)
         if not count then
            if err.AGAIN then break end
            peer.state = 'error'
            peer.msg = tostring(err)
         elseif count == 0 then
            peer.state = 'error'
            peer.msg = 'short write'
         else
            peer.pos = peer.pos + count
            assert(peer.pos <= len)
            if peer.pos == len then
               peer.pos = 0
               table.remove(peer.queue, 1)
            end
         end

         if peer.state == 'error' then
            if peer.state == 'error' then self:warn('%s', peer.msg) end
            peer.fd:close()
            table.remove(peers, i)
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
      local alarm = alarm_codec.decode(buf, len)
      self:handle_alarm(worker, alarm)
      channel:discard_message(len)
   end
end

function Manager:handle_alarm (worker, alarm)
   local fn, args = unpack(alarm)
   if fn == 'raise_alarm' then
      local key, args = alarm_codec.to_alarm(args)
      alarms.raise_alarm(key, args)
   end
   if fn == 'clear_alarm' then
      local key = alarm_codec.to_alarm(args)
      alarms.clear_alarm(key)
   end
   if fn == 'add_to_inventory' then
      local key, args = alarm_codec.to_alarm_type(args)
      alarms.do_add_to_inventory(key, args)
   end
   if fn == 'declare_alarm' then
      local key, args = alarm_codec.to_alarm(args)
      alarms.do_declare_alarm(key, args)
   end
end

function Manager:stop ()
   assert(self.sched:shutdown())
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
      self:run_scheduler()
      self:push_notifications_to_peers()
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
