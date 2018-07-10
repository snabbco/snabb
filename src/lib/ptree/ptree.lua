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
local yang = require("lib.yang.yang")
local data = require("lib.yang.data")
local util = require("lib.yang.util")
local schema = require("lib.yang.schema")
local rpc = require("lib.yang.rpc")
local state = require("lib.yang.state")
local path_mod = require("lib.yang.path")
local action_codec = require("lib.ptree.action_codec")
local alarm_codec = require("lib.ptree.alarm_codec")
local support = require("lib.ptree.support")
local channel = require("lib.ptree.channel")
local alarms = require("lib.yang.alarms")

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
   worker_default_scheduling = {default={busywait=true}},
   default_schema = {},
   log_level = {default=default_log_level},
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
   ret.setup_fn = conf.setup_fn
   ret.period = 1/conf.Hz
   ret.worker_default_scheduling = conf.worker_default_scheduling
   ret.workers = {}
   ret.state_change_listeners = {}
   ret.rpc_callee = rpc.prepare_callee('snabb-config-leader-v1')
   ret.rpc_handler = rpc.dispatch_handler(ret, 'rpc_')

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
   self.socket = open_socket(self.socket_file_name)
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

local function path_printer_for_grammar(grammar, path, format, print_default)
   local getter, subgrammar = path_mod.resolver(grammar, path)
   local printer
   if format == "xpath" then
      printer = data.xpath_printer_from_grammar(subgrammar, print_default, path)
   else
      printer = data.data_printer_from_grammar(subgrammar, print_default)
   end
   return function(data, file)
      return printer(getter(data), file)
   end
end

local function path_printer_for_schema(schema, path, is_config,
                                       format, print_default)
   local grammar = data.data_grammar_from_schema(schema, is_config)
   return path_printer_for_grammar(grammar, path, format, print_default)
end

local function path_printer_for_schema_by_name(schema_name, path, is_config,
                                               format, print_default)
   local schema = yang.load_schema_by_name(schema_name)
   return path_printer_for_schema(schema, path, is_config, format,
                                  print_default)
end

function Manager:rpc_get_config (args)
   local function getter()
      if args.schema ~= self.schema_name then
         return self:foreign_rpc_get_config(
            args.schema, args.path, args.format, args.print_default)
      end
      local printer = path_printer_for_schema_by_name(
         args.schema, args.path, true, args.format, args.print_default)
      local config = printer(self.current_configuration, yang.string_output_file())
      return { config = config }
   end
   local success, response = pcall(getter)
   if success then return response else return {status=1, error=response} end
end

function Manager:rpc_set_alarm_operator_state (args)
   local function getter()
      if args.schema ~= self.schema_name then
         return false, ("Set-operator-state operation not supported in"..
                        "'%s' schema"):format(args.schema)
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
         return false, ("Purge-alarms operation not supported in"..
                        "'%s' schema"):format(args.schema)
      end
      return { purged_alarms = alarms.purge_alarms(args) }
   end
   local success, response = pcall(purge)
   if success then return response else return {status=1, error=response} end
end

function Manager:rpc_compress_alarms (args)
   local function compress()
      if args.schema ~= self.schema_name then
         return false, ("Compress-alarms operation not supported in"..
                        "'%s' schema"):format(args.schema)
      end
      return { compressed_alarms = alarms.compress_alarms(args) }
   end
   local success, response = pcall(compress)
   if success then return response else return {status=1, error=response} end
end


local function path_parser_for_grammar(grammar, path)
   local getter, subgrammar = path_mod.resolver(grammar, path)
   return data.data_parser_from_grammar(subgrammar)
end

local function path_parser_for_schema(schema, path)
   local grammar = data.config_grammar_from_schema(schema)
   return path_parser_for_grammar(grammar, path)
end

local function path_parser_for_schema_by_name(schema_name, path)
   return path_parser_for_schema(yang.load_schema_by_name(schema_name), path)
end

local function path_setter_for_grammar(grammar, path)
   if path == "/" then
      return function(config, subconfig) return subconfig end
   end
   local head, tail = lib.dirname(path), lib.basename(path)
   local tail_path = path_mod.parse_path(tail)
   local tail_name, query = tail_path[1].name, tail_path[1].query
   if lib.equal(query, {}) then
      -- No query; the simple case.
      local getter, grammar = path_mod.resolver(grammar, head)
      assert(grammar.type == 'struct')
      local tail_id = data.normalize_id(tail_name)
      return function(config, subconfig)
         getter(config)[tail_id] = subconfig
         return config
      end
   end

   -- Otherwise the path ends in a query; it must denote an array or
   -- table item.
   local getter, grammar = path_mod.resolver(grammar, head..'/'..tail_name)
   if grammar.type == 'array' then
      local idx = path_mod.prepare_array_lookup(query)
      return function(config, subconfig)
         local array = getter(config)
         assert(idx <= #array)
         array[idx] = subconfig
         return config
      end
   elseif grammar.type == 'table' then
      local key = path_mod.prepare_table_lookup(grammar.keys,
                                                grammar.key_ctype, query)
      if grammar.string_key then
         key = key[data.normalize_id(grammar.string_key)]
         return function(config, subconfig)
            local tab = getter(config)
            assert(tab[key] ~= nil)
            tab[key] = subconfig
            return config
         end
      elseif grammar.key_ctype and grammar.value_ctype then
         return function(config, subconfig)
            getter(config):update(key, subconfig)
            return config
         end
      elseif grammar.key_ctype then
         return function(config, subconfig)
            local tab = getter(config)
            assert(tab[key] ~= nil)
            tab[key] = subconfig
            return config
         end
      else
         return function(config, subconfig)
            local tab = getter(config)
            for k,v in pairs(tab) do
               if lib.equal(k, key) then
                  tab[k] = subconfig
                  return config
               end
            end
            error("Not found")
         end
      end
   else
      error('Query parameters only allowed on arrays and tables')
   end
end

local function path_setter_for_schema(schema, path)
   local grammar = data.config_grammar_from_schema(schema)
   return path_setter_for_grammar(grammar, path)
end

function compute_set_config_fn (schema_name, path)
   return path_setter_for_schema(yang.load_schema_by_name(schema_name), path)
end

local function path_adder_for_grammar(grammar, path)
   local top_grammar = grammar
   local getter, grammar = path_mod.resolver(grammar, path)
   if grammar.type == 'array' then
      if grammar.ctype then
         -- It's an FFI array; have to create a fresh one, sadly.
         local setter = path_setter_for_grammar(top_grammar, path)
         local elt_t = data.typeof(grammar.ctype)
         local array_t = ffi.typeof('$[?]', elt_t)
         return function(config, subconfig)
            local cur = getter(config)
            local new = array_t(#cur + #subconfig)
            local i = 1
            for _,elt in ipairs(cur) do new[i-1] = elt; i = i + 1 end
            for _,elt in ipairs(subconfig) do new[i-1] = elt; i = i + 1 end
            return setter(config, util.ffi_array(new, elt_t))
         end
      end
      -- Otherwise we can add entries in place.
      return function(config, subconfig)
         local cur = getter(config)
         for _,elt in ipairs(subconfig) do table.insert(cur, elt) end
         return config
      end
   elseif grammar.type == 'table' then
      -- Invariant: either all entries in the new subconfig are added,
      -- or none are.
      if grammar.key_ctype and grammar.value_ctype then
         -- ctable.
         return function(config, subconfig)
            local ctab = getter(config)
            for entry in subconfig:iterate() do
               if ctab:lookup_ptr(entry.key) ~= nil then
                  error('already-existing entry')
               end
            end
            for entry in subconfig:iterate() do
               ctab:add(entry.key, entry.value)
            end
            return config
         end
      elseif grammar.string_key or grammar.key_ctype then
         -- cltable or string-keyed table.
         local pairs = grammar.key_ctype and cltable.pairs or pairs
         return function(config, subconfig)
            local tab = getter(config)
            for k,_ in pairs(subconfig) do
               if tab[k] ~= nil then error('already-existing entry') end
            end
            for k,v in pairs(subconfig) do tab[k] = v end
            return config
         end
      else
         -- Sad quadratic loop.
         return function(config, subconfig)
            local tab = getter(config)
            for key,val in pairs(tab) do
               for k,_ in pairs(subconfig) do
                  if lib.equal(key, k) then
                     error('already-existing entry', key)
                  end
               end
            end
            for k,v in pairs(subconfig) do tab[k] = v end
            return config
         end
      end
   else
      error('Add only allowed on arrays and tables')
   end
end

local function path_adder_for_schema(schema, path)
   local grammar = data.config_grammar_from_schema(schema)
   return path_adder_for_grammar(grammar, path)
end

function compute_add_config_fn (schema_name, path)
   return path_adder_for_schema(yang.load_schema_by_name(schema_name), path)
end
compute_add_config_fn = util.memoize(compute_add_config_fn)

local function path_remover_for_grammar(grammar, path)
   local top_grammar = grammar
   local head, tail = lib.dirname(path), lib.basename(path)
   local tail_path = path_mod.parse_path(tail)
   local tail_name, query = tail_path[1].name, tail_path[1].query
   local head_and_tail_name = head..'/'..tail_name
   local getter, grammar = path_mod.resolver(grammar, head_and_tail_name)
   if grammar.type == 'array' then
      if grammar.ctype then
         -- It's an FFI array; have to create a fresh one, sadly.
         local idx = path_mod.prepare_array_lookup(query)
         local setter = path_setter_for_grammar(top_grammar, head_and_tail_name)
         local elt_t = data.typeof(grammar.ctype)
         local array_t = ffi.typeof('$[?]', elt_t)
         return function(config)
            local cur = getter(config)
            assert(idx <= #cur)
            local new = array_t(#cur - 1)
            for i,elt in ipairs(cur) do
               if i < idx then new[i-1] = elt end
               if i > idx then new[i-2] = elt end
            end
            return setter(config, util.ffi_array(new, elt_t))
         end
      end
      -- Otherwise we can remove the entry in place.
      return function(config)
         local cur = getter(config)
         assert(i <= #cur)
         table.remove(cur, i)
         return config
      end
   elseif grammar.type == 'table' then
      local key = path_mod.prepare_table_lookup(grammar.keys,
                                                grammar.key_ctype, query)
      if grammar.string_key then
         key = key[data.normalize_id(grammar.string_key)]
         return function(config)
            local tab = getter(config)
            assert(tab[key] ~= nil)
            tab[key] = nil
            return config
         end
      elseif grammar.key_ctype and grammar.value_ctype then
         return function(config)
            getter(config):remove(key)
            return config
         end
      elseif grammar.key_ctype then
         return function(config)
            local tab = getter(config)
            assert(tab[key] ~= nil)
            tab[key] = nil
            return config
         end
      else
         return function(config)
            local tab = getter(config)
            for k,v in pairs(tab) do
               if lib.equal(k, key) then
                  tab[k] = nil
                  return config
               end
            end
            error("Not found")
         end
      end
   else
      error('Remove only allowed on arrays and tables')
   end
end

local function path_remover_for_schema(schema, path)
   local grammar = data.config_grammar_from_schema(schema)
   return path_remover_for_grammar(grammar, path)
end

function compute_remove_config_fn (schema_name, path)
   return path_remover_for_schema(yang.load_schema_by_name(schema_name), path)
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
   local parser = path_parser_for_schema_by_name(args.schema, path)
   self:update_configuration(compute_update_fn(args.schema, path),
                             verb, path, parser(args.config))
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
   local printer = path_printer_for_schema_by_name(
      schema_name, path, true, format, print_default)
   local config = printer(foreign_config, yang.string_output_file())
   return { config = config }
end
function Manager:foreign_rpc_get_state (schema_name, path, format,
                                       print_default)
   path = path_mod.normalize_path(path)
   local translate = self:get_translator(schema_name)
   local foreign_state = translate.get_state(self:get_native_state())
   local printer = path_printer_for_schema_by_name(
      schema_name, path, false, format, print_default)
   local state = printer(foreign_state, yang.string_output_file())
   return { state = state }
end
function Manager:foreign_rpc_set_config (schema_name, path, config_str)
   path = path_mod.normalize_path(path)
   local translate = self:get_translator(schema_name)
   local parser = path_parser_for_schema_by_name(schema_name, path)
   local updates = translate.set_config(self.current_configuration, path,
                                        parser(config_str))
   return self:apply_translated_rpc_updates(updates)
end
function Manager:foreign_rpc_add_config (schema_name, path, config_str)
   path = path_mod.normalize_path(path)
   local translate = self:get_translator(schema_name)
   local parser = path_parser_for_schema_by_name(schema_name, path)
   local updates = translate.add_config(self.current_configuration, path,
                                        parser(config_str))
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
      return self:handle_rpc_update_config(args, 'set', compute_set_config_fn)
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
      return self:handle_rpc_update_config(args, 'add', compute_add_config_fn)
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
      self:update_configuration(compute_remove_config_fn(args.schema, path),
                              'remove', path)
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
      local printer = path_printer_for_schema_by_name(
         self.schema_name, args.path, false, args.format, args.print_default)
      return { state = printer(state, yang.string_output_file()) }
   end
   local success, response = pcall(getter)
   if success then return response else return {status=1, error=response} end
end

function Manager:rpc_get_alarms_state (args)
   local function getter()
      assert(args.schema == "ietf-alarms")
      local printer = path_printer_for_schema_by_name(
         args.schema, args.path, false, args.format, args.print_default)
      local state = {
         alarms = alarms.get_state()
      }
      state = printer(state, yang.string_output_file())
      return { state = state }
   end
   local success, response = pcall(getter)
   if success then return response else return {status=1, error=response} end
end

function Manager:handle (payload)
   return rpc.handle_calls(self.rpc_callee, payload, self.rpc_handler)
end

local dummy_unix_sockaddr = S.t.sockaddr_un()

function Manager:handle_calls_from_peers()
   local peers = self.peers
   while true do
      local fd, err = self.socket:accept(dummy_unix_sockaddr)
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
      local visit_peer_again = false
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
         elseif ch == '' then
            if peer.len == 0 then
               peer.state = 'done'
            else
               peer.state = 'error'
               peer.msg = 'unexpected EOF'
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
         -- Uncomment to get backtraces.
         self.rpc_peer = peer
         -- local success, reply = true, self:handle(peer.payload)
         local success, reply = pcall(self.handle, self, peer.payload)
         self.rpc_peer = nil
         peer.payload = nil
         if success then
            assert(type(reply) == 'string')
            reply = #reply..'\n'..reply
            peer.state = 'reply'
            peer.buf = ffi.new('uint8_t[?]', #reply+1, reply)
            peer.pos = 0
            peer.len = #reply
         else
            peer.state = 'error'
            peer.msg = reply
         end
      end
      while peer.state == 'reply' do
         if peer.pos == peer.len then
            visit_peer_again = true
            peer.state = 'length'
            peer.buf, peer.pos = nil, nil
            peer.len = 0
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
      if peer.state == 'done' or peer.state == 'error' then
         if peer.state == 'error' then self:warn('%s', peer.msg) end
         peer.fd:close()
         table.remove(peers, i)
         if self.listen_peer == peer then self.listen_peer = nil end
      elseif not visit_peer_again then
         i = i + 1
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
   for _,peer in ipairs(self.peers) do peer.fd:close() end
   self.peers = {}
   self.socket:close()
   S.unlink(self.socket_file_name)

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
      self:handle_calls_from_peers()
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
