-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)
local ffi = require('ffi')
local app = require('core.app')
local data = require('lib.yang.data')
local yang = require('lib.yang.yang')
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
   return {{'call_app_method_with_blob', args}}
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
               psid_offset = psid_map.psid_offset,
               psid_len = psid_map.psid_len,
               psid = entry.key.psid
            },
            br_ipv6_addr = bt.br_address[entry.value.br+1],
         }
         ret[k] = v
      end
   end
   return ret
end

local function ietf_softwire_translator ()
   local ret = {}
   function ret.get_config(native_config)
      -- Such nesting, very standard, wow
      local br_instance, br_instance_key_t =
         cltable_for_grammar(get_ietf_br_instance_grammar())
      br_instance[br_instance_key_t({id=1})] = {
         -- FIXME
         tunnel_payload_mtu = 0,
         tunnel_path_mru = 0,
         binding_table = {
            binding_entry = ietf_binding_table_from_native(
               native_config.softwire_config.binding_table)
         }
      }
      return {
         softwire_config = {
            binding = {
               br = {
                  br_instances = { br_instance = br_instance }
               }
            }
         }
      }
   end
   ret.get_config = memoize1(ret.get_config)
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
   ret.get_state = memoize1(ret.get_state)
   function ret.set_config(native_config, path, data)
      error('unimplemented')
   end
   function ret.add_config(native_config, path, data)
      error('unimplemented')
   end
   function ret.remove_config(native_config, path)
      error('unimplemented')
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
