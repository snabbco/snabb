-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)
local ffi = require('ffi')
local app = require('core.app')
local equal = require('core.lib').equal
local dirname = require('core.lib').dirname
local data = require('lib.yang.data')
local ipv4_ntop = require('lib.yang.util').ipv4_ntop
local ipv6 = require('lib.protocol.ipv6')
local yang = require('lib.yang.yang')
local ctable = require('lib.ctable')
local cltable = require('lib.cltable')
local path_mod = require('lib.yang.path')
local generic = require('apps.config.support').generic_schema_config_support

local function add_softwire_entry_actions(app_graph, entries)
   assert(app_graph.apps['lwaftr'])
   local ret = {}
   for entry in entries:iterate() do
      local blob = entries.entry_type()
      ffi.copy(blob, entry, ffi.sizeof(blob))
      local args = {'lwaftr', 'add_softwire_entry', blob}
      table.insert(ret, {'call_app_method_with_blob', args})
   end
   table.insert(ret, {'commit', {}})
   return ret
end

local softwire_grammar
local function get_softwire_grammar()
   if not softwire_grammar then
      local schema = yang.load_schema_by_name('snabb-softwire-v1')
      local grammar = data.data_grammar_from_schema(schema)
      softwire_grammar =
         assert(grammar.members['softwire-config'].
                   members['binding-table'].members['softwire'])
   end
   return softwire_grammar
end

local function remove_softwire_entry_actions(app_graph, path)
   assert(app_graph.apps['lwaftr'])
   path = path_mod.parse_path(path)
   local grammar = get_softwire_grammar()
   local key = path_mod.prepare_table_lookup(
      grammar.keys, grammar.key_ctype, path[#path].query)
   local args = {'lwaftr', 'remove_softwire_entry', key}
   return {{'call_app_method_with_blob', args}, {'commit', {}}}
end

local function compute_config_actions(old_graph, new_graph, to_restart,
                                      verb, path, arg)
   if verb == 'add' and path == '/softwire-config/binding-table/softwire' then
      return add_softwire_entry_actions(new_graph, arg)
   elseif (verb == 'remove' and
           path:match('^/softwire%-config/binding%-table/softwire')) then
      return remove_softwire_entry_actions(new_graph, path)
   else
      return generic.compute_config_actions(
         old_graph, new_graph, to_restart, verb, path, arg)
   end
end

local function update_mutable_objects_embedded_in_app_initargs(
      in_place_dependencies, app_graph, schema_name, verb, path, arg)
   if verb == 'add' and path == '/softwire-config/binding-table/softwire' then
      return in_place_dependencies
   elseif (verb == 'remove' and
           path:match('^/softwire%-config/binding%-table/softwire')) then
      return in_place_dependencies
   else
      return generic.update_mutable_objects_embedded_in_app_initargs(
         in_place_dependencies, app_graph, schema_name, verb, path, arg)
   end
end

local function compute_apps_to_restart_after_configuration_update(
      schema_name, configuration, verb, path, in_place_dependencies)
   if verb == 'add' and path == '/softwire-config/binding-table/softwire' then
      return {}
   elseif (verb == 'remove' and
           path:match('^/softwire%-config/binding%-table/softwire')) then
      return {}
   else
      return generic.compute_apps_to_restart_after_configuration_update(
         schema_name, configuration, verb, path, in_place_dependencies)
   end
end

local function memoize1(f)
   local memoized_arg, memoized_result
   return function(arg)
      if arg == memoized_arg then return memoized_result end
      memoized_result = f(arg)
      memoized_arg = arg
      return memoized_result
   end
end

local ietf_br_instance_grammar
local function get_ietf_br_instance_grammar()
   if not ietf_br_instance_grammar then
      local schema = yang.load_schema_by_name('ietf-softwire')
      local grammar = data.data_grammar_from_schema(schema)
      grammar = assert(grammar.members['softwire-config'])
      grammar = assert(grammar.members['binding'])
      grammar = assert(grammar.members['br'])
      grammar = assert(grammar.members['br-instances'])
      grammar = assert(grammar.members['br-instance'])
      ietf_br_instance_grammar = grammar
   end
   return ietf_br_instance_grammar
end

local ietf_softwire_grammar
local function get_ietf_softwire_grammar()
   if not ietf_softwire_grammar then
      local grammar = get_ietf_br_instance_grammar()
      grammar = assert(grammar.values['binding-table'])
      grammar = assert(grammar.members['binding-entry'])
      ietf_softwire_grammar = grammar
   end
   return ietf_softwire_grammar
end

local function cltable_for_grammar(grammar)
   assert(grammar.key_ctype)
   assert(not grammar.value_ctype)
   local key_t = data.typeof(grammar.key_ctype)
   return cltable.new({key_type=key_t}), key_t
end

local function ietf_binding_table_from_native(bt)
   local ret, key_t = cltable_for_grammar(get_ietf_softwire_grammar())
   local psid_key_t = data.typeof('struct { uint32_t ipv4; }')
   for entry in bt.softwire:iterate() do
      local psid_map = bt.psid_map[psid_key_t({ipv4=entry.key.ipv4})]
      if psid_map then
         local k = key_t({ binding_ipv6info = entry.value.b4_ipv6 })
         local v = {
            binding_ipv4_addr = entry.key.ipv4,
            port_set = {
               psid_offset = psid_map.reserved_ports_bit_count,
               psid_len = psid_map.psid_length,
               psid = entry.key.psid
            },
            br_ipv6_addr = bt.br_address[entry.value.br],
         }
         ret[k] = v
      end
   end
   return ret
end

local function schema_getter(schema_name, path)
   local schema = yang.load_schema_by_name(schema_name)
   local grammar = data.data_grammar_from_schema(schema)
   return path_mod.resolver(grammar, path)
end

local function snabb_softwire_getter(path)
   return schema_getter('snabb-softwire-v1', path)
end

local function ietf_softwire_getter(path)
   return schema_getter('ietf-softwire', path)
end

local function native_binding_table_from_ietf(ietf)
   local _, psid_map_grammar =
      snabb_softwire_getter('/softwire-config/binding-table/psid-map')
   local psid_map_key_t = data.typeof(psid_map_grammar.key_ctype)
   local psid_map = cltable.new({key_type=psid_map_key_t})
   local br_address = {}
   local br_address_by_ipv6 = {}
   local _, softwire_grammar =
      snabb_softwire_getter('/softwire-config/binding-table/softwire')
   local softwire_key_t = data.typeof(softwire_grammar.key_ctype)
   local softwire_value_t = data.typeof(softwire_grammar.value_ctype)
   local softwire = ctable.new({key_type=softwire_key_t,
                                value_type=softwire_value_t})
   for k,v in cltable.pairs(ietf) do
      local br_address_key = ipv6:ntop(v.br_ipv6_addr)
      local br = br_address_by_ipv6[br_address_key]
      if not br then
         table.insert(br_address, v.br_ipv6_addr)
         br = #br_address
         br_address_by_ipv6[br_address_key] = br
      end
      local psid_key = psid_map_key_t({addr=v.binding_ipv4_addr})
      if not psid_map[psid_key] then
         psid_map[psid_key] = {psid_length=v.port_set.psid_len,
                               reserved_ports_bit_count=v.port_set.psid_offset}
      end
      softwire:add(softwire_key_t({ipv4=v.binding_ipv4_addr,
                                   psid=v.port_set.psid}),
                   softwire_value_t({br=br, b4_ipv6=k.binding_ipv6info}))
   end
   return {psid_map=psid_map, br_address=br_address, softwire=softwire}
end

local function serialize_binding_table(bt)
   local _, grammar = snabb_softwire_getter('/softwire-config/binding-table')
   local printer = data.data_printer_from_grammar(grammar)
   return printer(bt, yang.string_output_file())
end

local uint64_ptr_t = ffi.typeof('uint64_t*')
function ipv6_equals(a, b)
   local x, y = ffi.cast(uint64_ptr_t, a), ffi.cast(uint64_ptr_t, b)
   return x[0] == y[0] and x[1] == y[1]
end

local function ietf_softwire_translator ()
   local ret = {}
   local cached_config
   function ret.get_config(native_config)
      if cached_config ~= nil then return cached_config end
      local br_instance, br_instance_key_t =
         cltable_for_grammar(get_ietf_br_instance_grammar())
      br_instance[br_instance_key_t({id=1})] = {
         tunnel_payload_mtu = native_config.softwire_config.internal_interface.mtu,
         tunnel_path_mru = native_config.softwire_config.external_interface.mtu,
         -- FIXME: What it should map to?
         softwire_num_threshold = 0xffffffff,
         binding_table = {
            binding_entry = ietf_binding_table_from_native(
               native_config.softwire_config.binding_table)
         }
      }
      cached_config = {
         softwire_config = {
            binding = {
               br = {
                  br_instances = { br_instance = br_instance }
               }
            }
         }
      }
      return cached_config
   end
   function ret.get_state(native_state)
      -- Even though this is a different br-instance node, it is a
      -- cltable with the same key type, so just re-use the key here.
      local br_instance, br_instance_key_t =
         cltable_for_grammar(get_ietf_br_instance_grammar())
      br_instance[br_instance_key_t({id=1})] = {
         -- FIXME!
         sentPacket = 0,
         sentByte = 0,
         rcvdPacket = 0,
         rcvdByte = 0,
         droppedPacket = 0,
         droppedByte = 0
      }
      return {
         softwire_state = {
            binding = {
               br = {
                  br_instances = { br_instance = br_instance }
               }
            }
         }
      }
   end
   local function sets_whole_table(path, count)
      if #path > count then return false end
      if #path == count then
         for k,v in pairs(path[#path].query) do return false end
      end
      return true
   end
   function ret.set_config(native_config, path_str, arg)
      path = path_mod.parse_path(path_str)
      local br_instance_paths = {'softwire-config', 'binding', 'br',
                                 'br-instances', 'br-instance'}
      local bt_paths = {'binding-table', 'binding-entry'}

      -- Handle special br attributes (tunnel-payload-mtu, tunnel-path-mru, softwire-num-threshold)
      if #path > #br_instance_paths then
         if path[#path].name == 'tunnel-payload-mtu' then
            return {{'set', {schema='snabb-softwire-v1',
                     path="/softwire-config/internal-interface/mtu",
                     config=tostring(arg)}}}
         end
         if path[#path].name == 'tunnel-path-mru' then
            return {{'set', {schema='snabb-softwire-v1',
                     path="/softwire-config/external-interface/mtu",
                     config=tostring(arg)}}}
         end
         if path[#path].name == 'softwire-num-threshold' then
            -- FIXME: Do nothing.
            return {}
         end
         error('unrecognized leaf: '..path[#path].name)
      end

      -- Two kinds of updates: setting the whole binding table, or
      -- updating one entry.
      if sets_whole_table(path, #br_instance_paths + #bt_paths) then
         -- Setting the whole binding table.
         if sets_whole_table(path, #br_instance_paths) then
            for i=#path+1,#br_instance_paths do
               arg = arg[data.normalize_id(br_instance_paths[i])]
            end
            local instance
            for k,v in cltable.pairs(arg) do
               if instance then error('multiple instances in config') end
               if k.id ~= 1 then error('instance id not 1: '..tostring(k.id)) end
               instance = v
            end
            if not instance then error('no instances in config') end
            arg = instance
         end
         for i=math.max(#path-#br_instance_paths,0)+1,#bt_paths do
            arg = arg[data.normalize_id(bt_paths[i])]
         end
         local bt = native_binding_table_from_ietf(arg)
         return {{'set', {schema='snabb-softwire-v1',
                          path='/softwire-config/binding-table', 
                          config=serialize_binding_table(bt)}}}
      else
         -- An update to an existing entry.  First, get the existing entry.
         local config = ret.get_config(native_config)
         local entry_path = path_str
         local entry_path_len = #br_instance_paths + #bt_paths
         for i=entry_path_len+1, #path do
            entry_path = dirname(entry_path)
         end
         local old = ietf_softwire_getter(entry_path)(config)
         -- Now figure out what the new entry should look like.
         local new
         if #path == entry_path_len then
            new = arg
         else
            new = {
               port_set = {
                  psid_offset = old.port_set.psid_offset,
                  psid_len = old.port_set.psid_len,
                  psid = old.port_set.psid
               },
               binding_ipv4_addr = old.binding_ipv4_addr,
               br_ipv6_addr = old.br_ipv6_addr
            }
            if path[entry_path_len + 1].name == 'port-set' then
               if #path == entry_path_len + 1 then
                  new.port_set = arg
               else
                  local k = data.normalize_id(path[#path].name)
                  new.port_set[k] = arg
               end
            elseif path[#path].name == 'binding-ipv4-addr' then
               new.binding_ipv4_addr = arg
            elseif path[#path].name == 'br-ipv6-addr' then
               new.br_ipv6_addr = arg
            else
               error('bad path element: '..path[#path].name)
            end
         end
         -- Apply changes.  Start by ensuring that there's a br-address
         -- entry for this softwire, and ensuring that the port-set
         -- changes are compatible with the existing configuration.
         local updates = {}
         local softwire_path = '/softwire-config/binding-table/softwire'
         local psid_map_path = '/softwire-config/binding-table/psid-map'
         local br_address_path = '/softwire-config/binding-table/br-address'
         local new_br
         local bt = native_config.softwire_config.binding_table
         for i,br in ipairs(bt.br_address) do
            if ipv6_equals(br, new.br_ipv6_addr) then
               new_br = i; break
            end
         end
         if new_br == nil then
            new_br = #bt.br_address + 1
            table.insert(updates,
                         {'add', {schema='snabb-softwire-v1',
                                  path=br_address_path,
                                  config=ipv6:ntop(new.br_ipv6_addr)}})
         end
         if new.binding_ipv4_addr ~= old.binding_ipv4_addr then
            local psid_key_t = data.typeof('struct { uint32_t ipv4; }')
            local psid_map_entry =
               bt.psid_map[psid_key_t({ipv4=new.binding_ipv4_addr})]
            if psid_map_entry == nil then
               local config_str = string.format(
                  "{ addr %s; psid-length %s; reserved-ports-bit-count %s; }",
                  ipv4_ntop(new.binding_ipv4_addr), new.port_set.psid_len,
                  new.port_set.psid_offset)
               table.insert(updates,
                            {'add', {schema='snabb-softwire-v1',
                                     path=psid_map_path,
                                     config=config_str}})
            elseif (psid_map_entry.psid_length ~= new.port_set.psid_len or
                    psid_map_entry.reserved_ports_bit_count ~=
                      new.port_set.psid_offset) then
               -- The Snabb lwAFTR is restricted to having the same PSID
               -- parameters for every softwire on an IPv4.  Here we
               -- have a request to have a softwire whose paramters
               -- differ from those already installed for this IPv4
               -- address.  We would need to verify that there is no
               -- other softwire on this address.
               error('changing psid params unimplemented')
            end
         elseif (new.port_set.psid_offset ~= old.port_set.psid_offset or
                 new.port_set.psid_len ~= old.port_set.psid_len) then
            -- See comment above.
            error('changing psid params unimplemented')
         end
         -- OK, psid_map and br_address taken care of, let's just remove
         -- this softwire entry and add a new one.
         local function q(ipv4, psid)
            return string.format('[ipv4=%s][psid=%s]', ipv4_ntop(ipv4), psid)
         end
         local old_query = q(old.binding_ipv4_addr, old.port_set.psid)
         -- FIXME: This remove will succeed but the add could fail if
         -- there's already a softwire with this IPv4 and PSID.  We need
         -- to add a check here that the IPv4/PSID is not present in the
         -- binding table.
         table.insert(updates,
                      {'remove', {schema='snabb-softwire-v1',
                                  path=softwire_path..old_query}})
         local config_str = string.format(
            '{ ipv4 %s; psid %s; br %s; b4-ipv6 %s; }',
            ipv4_ntop(new.binding_ipv4_addr), new.port_set.psid,
            new_br, path[entry_path_len].query['binding-ipv6info'])
         table.insert(updates,
                      {'add', {schema='snabb-softwire-v1',
                               path=softwire_path,
                               config=config_str}})
         return updates
      end
   end
   function ret.add_config(native_config, path, data)
      if path ~= ('/softwire-config/binding/br/br-instances'..
                     '/br-instance[id=1]/binding-table/binding-entry') then
         error('unsupported path: '..path)
      end
      local config = ret.get_config(native_config)
      local ietf_bt = ietf_softwire_getter(path)(config)
      local old_bt = native_config.softwire_config.binding_table
      local new_bt = native_binding_table_from_ietf(data)
      local updates = {}
      local softwire_path = '/softwire-config/binding-table/softwire'
      local psid_map_path = '/softwire-config/binding-table/psid-map'
      local br_address_path = '/softwire-config/binding-table/br-address'
      -- Add new psid_map entries.
      for k,v in cltable.pairs(new_bt.psid_map) do
         if old_bt.psid_map[k] then
            if not equal(old_bt.psid_map[k], v) then
               error('changing psid params unimplemented: '..k.addr)
            end
         else
            local config_str = string.format(
               "{ addr %s; psid-length %s; reserved-ports-bit-count %s; }",
               ipv4_ntop(k.addr), v.psid_length, v.reserved_ports_bit_count)
            table.insert(updates,
                         {'add', {schema='snabb-softwire-v1',
                                  path=psid_map_path,
                                  config=config_str}})
         end
      end
      -- Remap br-address entries.
      local br_address_map = {}
      local br_address_count = #old_bt.br_address
      for _,new_br_address in ipairs(new_bt.br_address) do
         local idx
         for i,old_br_address in ipairs(old_bt.br_address) do
            if ipv6_equals(old_br_address, new_br_address) then
               idx = i
               break
            end
         end
         if not idx then
            br_address_count = br_address_count + 1
            idx = br_address_count
            table.insert(updates,
                         {'add', {schema='snabb-softwire-v1',
                                  path=br_address_path,
                                  config=ipv6:ntop(new_br_address)}})
         end
         table.insert(br_address_map, idx)
      end
      -- Add softwires.
      local additions = {}
      for entry in new_bt.softwire:iterate() do
         if old_bt.softwire:lookup_ptr(entry) then
            error('softwire already present in table: '..
                     inet_ntop(entry.key.ipv4)..'/'..entry.key.psid)
         end
         local config_str = string.format(
            '{ ipv4 %s; psid %s; br %s; b4-ipv6 %s; }',
            ipv4_ntop(entry.key.ipv4), entry.key.psid,
            br_address_map[entry.value.br], ipv6:ntop(entry.value.b4_ipv6))
         table.insert(additions, config_str)
      end
      table.insert(updates,
                   {'add', {schema='snabb-softwire-v1',
                            path=softwire_path,
                            config=table.concat(additions, '\n')}})
      return updates
   end
   function ret.remove_config(native_config, path)
      local ietf_binding_table_path =
         '/softwire-config/binding/br/br-instances/br-instance[id=1]/binding-table'
      local softwire_path = '/softwire-config/binding-table/softwire'
      if (dirname(path) ~= ietf_binding_table_path or
          path:sub(-1) ~= ']') then
         error('unsupported path: '..path)
      end
      local config = ret.get_config(native_config)
      local entry = ietf_softwire_getter(path)(config)
      local function q(ipv4, psid)
         return string.format('[ipv4=%s][psid=%s]', ipv4_ntop(ipv4), psid)
      end
      local query = q(entry.binding_ipv4_addr, entry.port_set.psid)
      return {{'remove', {schema='snabb-softwire-v1',
                          path=softwire_path..query}}}
   end
   function ret.pre_update(native_config, verb, path, data)
      -- Given the notification that the native config is about to be
      -- updated, make our cached config follow along if possible (and
      -- if we have one).  Otherwise throw away our cached config; we'll
      -- re-make it next time.
      if cached_config == nil then return end
      if (verb == 'remove' and
          path:match('^/softwire%-config/binding%-table/softwire')) then
         -- Remove a softwire.
         local value = snabb_softwire_getter(path)(native_config)
         local br = cached_config.softwire_config.binding.br
         for _,instance in cltable.pairs(br.br_instances.br_instance) do
            local grammar = get_ietf_softwire_grammar()
            local key = path_mod.prepare_table_lookup(
               grammar.keys, grammar.key_ctype, {['binding-ipv6info']='::'})
            key.binding_ipv6info = value.b4_ipv6
            assert(instance.binding_table.binding_entry[key] ~= nil)
            instance.binding_table.binding_entry[key] = nil
         end
      elseif (verb == 'add' and
              path == '/softwire-config/binding-table/softwire') then
         local bt = native_config.softwire_config.binding_table
         for k,v in cltable.pairs(
            ietf_binding_table_from_native(
               { psid_map = bt.psid_map, br_address = bt.br_address,
                 softwire = data })) do
            local br = cached_config.softwire_config.binding.br
            for _,instance in cltable.pairs(br.br_instances.br_instance) do
               instance.binding_table.binding_entry[k] = v
            end
         end
      else
         cached_config = nil
      end
   end
   return ret
end

function get_config_support()
   return {
      compute_config_actions = compute_config_actions,
      update_mutable_objects_embedded_in_app_initargs =
         update_mutable_objects_embedded_in_app_initargs,
      compute_apps_to_restart_after_configuration_update =
         compute_apps_to_restart_after_configuration_update,
      translators = { ['ietf-softwire'] = ietf_softwire_translator () }
   }
end
