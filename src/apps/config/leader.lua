-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local lib = require("core.lib")
local cltable = require("lib.cltable")
local yang = require("lib.yang.yang")
local data = require("lib.yang.data")
local util = require("lib.yang.util")
local schema = require("lib.yang.schema")
local rpc = require("lib.yang.rpc")
local state = require("lib.yang.state")
local path_mod = require("lib.yang.path")
local app = require("core.app")
local shm = require("core.shm")
local app_graph = require("core.config")
local action_codec = require("apps.config.action_codec")
local support = require("apps.config.support")
local channel = require("apps.config.channel")

Leader = {
   config = {
      socket_file_name = {default='config-leader-socket'},
      setup_fn = {required=true},
      -- Could relax this requirement.
      initial_configuration = {required=true},
      schema_name = {required=true},
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
   ret.schema_name = conf.schema_name
   ret.support = support.load_schema_config_support(conf.schema_name)
   ret.socket = open_socket(ret.socket_file_name)
   ret.peers = {}
   ret.setup_fn = conf.setup_fn
   ret.period = 1/conf.Hz
   ret.next_time = app.now()
   ret.followers = {}
   for _,pid in ipairs(conf.follower_pids) do
      table.insert(ret.followers, { pid=pid, queue={} })
   end
   ret.rpc_callee = rpc.prepare_callee('snabb-config-leader-v1')
   ret.rpc_handler = rpc.dispatch_handler(ret, 'rpc_')

   ret:set_initial_configuration(conf.initial_configuration)

   return ret
end

function Leader:set_initial_configuration (configuration)
   self.current_configuration = configuration
   self.current_app_graph = self.setup_fn(configuration)
   self.current_in_place_dependencies = {}
   self.current_in_place_dependencies =
      self.support.update_mutable_objects_embedded_in_app_initargs (
         {}, self.current_app_graph, self.schema_name, 'load', '/',
         self.current_configuration)
   local initial_app_graph = app_graph.new() -- Empty.
   local actions = self.support.compute_config_actions(
      initial_app_graph, self.current_app_graph, {}, 'load')
   self:enqueue_config_actions(actions)
end

function Leader:take_follower_message_queue ()
   local actions = self.config_action_queue
   self.config_action_queue = nil
   return actions
end

local verbose = os.getenv('SNABB_LEADER_VERBOSE') and true

function Leader:enqueue_config_actions (actions)
   local messages = {}
   for _,action in ipairs(actions) do
      if verbose then print('encode', action[1], unpack(action[2])) end
      local buf, len = action_codec.encode(action)
      table.insert(messages, { buf=buf, len=len })
   end
   for _,follower in ipairs(self.followers) do
      for _,message in ipairs(messages) do
         table.insert(follower.queue, message)
      end
   end
end

function Leader:rpc_describe (args)
   local alternate_schemas = {}
   for schema_name, translator in pairs(self.support.translators) do
      table.insert(alternate_schemas, schema_name)
   end
   return { native_schema = self.schema_name,
            alternate_schema = alternate_schemas,
            capability = schema.get_default_capabilities() }
end

local function path_printer_for_grammar(grammar, path, opts)
   local getter, subgrammar = path_mod.resolver(grammar, path)
   local printer
   if opts.format == "xpath" then
      printer = data.xpath_printer_from_grammar(subgrammar, opts.print_default, path)
   else
      printer = data.data_printer_from_grammar(subgrammar, opts.print_default)
   end
   return function(data, file)
      return printer(getter(data), file)
   end
end

local function path_printer_for_schema(schema, path, opts)
   return path_printer_for_grammar(data.data_grammar_from_schema(schema), path, opts)
end

local function path_printer_for_schema_by_name(schema_name, path, opts)
   return path_printer_for_schema(yang.load_schema_by_name(schema_name), path, opts)
end

function Leader:rpc_get_config (args)
   local function getter()
      if args.schema ~= self.schema_name then
         return self:foreign_rpc_get_config(args.schema, args.path, args)
      end
      local printer = path_printer_for_schema_by_name(args.schema, args.path, args)
      local config = printer(self.current_configuration, yang.string_output_file())
      return { config = config }
   end
   local success, response = pcall(getter)
   if success then return response else return {status=1, error=response} end
end

local function path_parser_for_grammar(grammar, path)
   local getter, subgrammar = path_mod.resolver(grammar, path)
   return data.data_parser_from_grammar(subgrammar)
end

local function path_parser_for_schema(schema, path)
   return path_parser_for_grammar(data.data_grammar_from_schema(schema), path)
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
   return path_setter_for_grammar(data.data_grammar_from_schema(schema), path)
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
               if tab[k] ~= nil then error('already-existing entry', k) end
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
   return path_adder_for_grammar(data.data_grammar_from_schema(schema), path)
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
   return path_remover_for_grammar(data.data_grammar_from_schema(schema), path)
end

function compute_remove_config_fn (schema_name, path)
   return path_remover_for_schema(yang.load_schema_by_name(schema_name), path)
end

function Leader:notify_pre_update (config, verb, path, ...)
   for _,translator in pairs(self.support.translators) do
      translator.pre_update(config, verb, path, ...)
   end
end

function Leader:update_configuration (update_fn, verb, path, ...)
   self:notify_pre_update(self.current_configuration, verb, path, ...)
   local to_restart =
      self.support.compute_apps_to_restart_after_configuration_update (
         self.schema_name, self.current_configuration, verb, path,
         self.current_in_place_dependencies, ...)
   local new_config = update_fn(self.current_configuration, ...)
   local new_app_graph = self.setup_fn(new_config)
   local actions = self.support.compute_config_actions(
      self.current_app_graph, new_app_graph, to_restart, verb, path, ...)
   self:enqueue_config_actions(actions)
   self.current_app_graph = new_app_graph
   self.current_configuration = new_config
   self.current_in_place_dependencies =
      self.support.update_mutable_objects_embedded_in_app_initargs (
         self.current_in_place_dependencies, self.current_app_graph,
         verb, path, ...)
end

function Leader:handle_rpc_update_config (args, verb, compute_update_fn)
   local path = path_mod.normalize_path(args.path)
   local parser = path_parser_for_schema_by_name(args.schema, path)
   self:update_configuration(compute_update_fn(args.schema, path),
                             verb, path, parser(args.config))
   return {}
end

function Leader:get_translator (schema_name)
   local translator = self.support.translators[schema_name]
   if translator then return translator end
   error('unsupported schema: '..schema_name)
end
function Leader:apply_translated_rpc_updates (updates)
   for _,update in ipairs(updates) do
      local verb, args = unpack(update)
      local method = assert(self['rpc_'..verb..'_config'])
      method(self, args)
   end
   return {}
end
function Leader:foreign_rpc_get_config (schema_name, path, args)
   path = path_mod.normalize_path(path)
   local translate = self:get_translator(schema_name)
   local foreign_config = translate.get_config(self.current_configuration)
   local printer = path_printer_for_schema_by_name(schema_name, path, args)
   local config = printer(foreign_config, yang.string_output_file())
   return { config = config }
end
function Leader:foreign_rpc_get_state (schema_name, path, args)
   path = path_mod.normalize_path(path)
   local translate = self:get_translator(schema_name)
   local native_state = state.show_state(self.schema_name, S.getpid(), "/")
   local foreign_state = translate.get_state(native_state)
   local printer = path_printer_for_schema_by_name(schema_name, path, args)
   local config = printer(foreign_state, yang.string_output_file())
   return { state = config }
end
function Leader:foreign_rpc_set_config (schema_name, path, config_str)
   path = path_mod.normalize_path(path)
   local translate = self:get_translator(schema_name)
   local parser = path_parser_for_schema_by_name(schema_name, path)
   local updates = translate.set_config(self.current_configuration, path,
                                        parser(config_str))
   return self:apply_translated_rpc_updates(updates)
end
function Leader:foreign_rpc_add_config (schema_name, path, config_str)
   path = path_mod.normalize_path(path)
   local translate = self:get_translator(schema_name)
   local parser = path_parser_for_schema_by_name(schema_name, path)
   local updates = translate.add_config(self.current_configuration, path,
                                        parser(config_str))
   return self:apply_translated_rpc_updates(updates)
end
function Leader:foreign_rpc_remove_config (schema_name, path)
   path = path_mod.normalize_path(path)
   local translate = self:get_translator(schema_name)
   local updates = translate.remove_config(self.current_configuration, path)
   return self:apply_translated_rpc_updates(updates)
end

function Leader:rpc_set_config (args)
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

function Leader:rpc_add_config (args)
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

function Leader:rpc_remove_config (args)
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

function Leader:rpc_attach_listener (args)
   local function attacher()
      if self.listen_peer ~= nil then error('Listener already attached') end
      self.listen_peer = self.rpc_peer
      return {}
   end
   local success, response = pcall(attacher)
   if success then return response else return {status=1, error=response} end
end

function Leader:rpc_get_state (args)
   local function getter()
      if args.schema ~= self.schema_name then
            return self:foreign_rpc_get_state(args.schema, args.path, args)
      end
      local printer = path_printer_for_schema_by_name(self.schema_name, args.path, args)
      local s = {}
      for _, follower in pairs(self.followers) do
         for k,v in pairs(state.show_state(self.schema_name, follower.pid, args.path)) do
            s[k] = v
         end
      end
      return {state=printer(s, yang.string_output_file())}
   end
   local success, response = pcall(getter)
   if success then return response else return {status=1, error=response} end
end
function Leader:handle (payload)
   return rpc.handle_calls(self.rpc_callee, payload, self.rpc_handler)
end

local dummy_unix_sockaddr = S.t.sockaddr_un()

function Leader:handle_calls_from_peers()
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
         if peer.state == 'error' then print('error: '..peer.msg) end
         peer.fd:close()
         table.remove(peers, i)
         if self.listen_peer == peer then self.listen_peer = nil end
      elseif not visit_peer_again then
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
                 {setup_fn=setup_fn, follower_pids={S.getpid()},
                  -- Use a schema with no data nodes, just for
                  -- testing.
                  schema_name='ietf-inet-types', initial_configuration={}})
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
