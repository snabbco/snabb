-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local data = require("lib.yang.data")
local value = require("lib.yang.value")
local schema = require("lib.yang.schema")
local parse_path = require("lib.yang.path").parse_path
local util = require("lib.yang.util")
local normalize_id = data.normalize_id

local function table_keys(t)
   local ret = {}
   for k, v in pairs(t) do table.insert(ret, k) end
   return ret
end

function prepare_array_lookup(query)
   if not lib.equal(table_keys(query), {"position()"}) then
      error("Arrays can only be indexed by position.")
   end
   local idx = tonumber(query["position()"])
   if idx < 1 or idx ~= math.floor(idx) then
      error("Arrays can only be indexed by positive integers.")
   end
   return idx
end

function prepare_table_lookup(keys, ctype, query)
   local static_key = ctype and data.typeof(ctype)() or {}
   for k,_ in pairs(query) do
      if not keys[k] then error("'"..k.."' is not a table key") end
   end
   for k,grammar in pairs(keys) do
      local v = query[k] or grammar.default
      if v == nil then
         error("Table query missing required key '"..k.."'")
      end
      local key_primitive_type = grammar.argument_type.primitive_type
      local parser = value.types[key_primitive_type].parse
      static_key[normalize_id(k)] = parser(v, 'path query value')
   end
   return static_key
end

-- Returns a resolver for a particular schema and *lua* path.
function resolver(grammar, path_string)
   local function ctable_getter(key, getter)
      return function(data)
         local data = getter(data):lookup_ptr(key)
         if data == nil then error("Not found") end
         return data.value
      end
   end
   local function table_getter(key, getter)
      return function(data)
         local data = getter(data)[key]
         if data == nil then error("Not found") end
         return data
      end
   end
   local function slow_table_getter(key, getter)
      return function(data)
         for k,v in pairs(getter(data)) do
            if lib.equal(k, key) then return v end
         end
         error("Not found")
      end
   end
   local function compute_table_getter(grammar, key, getter)
      if grammar.string_key then
         return table_getter(key[normalize_id(grammar.string_key)], getter)
      elseif grammar.key_ctype and grammar.value_ctype then
         return ctable_getter(key, getter)
      elseif grammar.key_ctype then
         return table_getter(key, getter)
      else
         return slow_table_getter(key, getter)
      end
   end
   local function handle_table_query(grammar, query, getter)
      local key = prepare_table_lookup(grammar.keys, grammar.key_ctype, query)
      local child_grammar = {type="struct", members=grammar.values,
                             ctype=grammar.value_ctype}
      local child_getter = compute_table_getter(grammar, key, getter)
      return child_getter, child_grammar
   end
   local function handle_array_query(grammar, query, getter)
      local idx = prepare_array_lookup(query)
      -- Pretend that array elements are scalars.
      local child_grammar = {type="scalar", argument_type=grammar.element_type,
                             ctype=grammar.ctype}
      local function child_getter(data)
         local array = getter(data)
         if idx > #array then error("Index out of bounds") end
         return array[idx]
      end
      return child_getter, child_grammar
   end
   local function handle_query(grammar, query, getter)
      if lib.equal(table_keys(query), {}) then return getter, grammar end
      if grammar.type == 'array' then
         return handle_array_query(grammar, query, getter)
      elseif grammar.type == 'table' then
         return handle_table_query(grammar, query, getter)
      else
         error("Path query parameters only supported for structs and tables.")
      end
   end
   local function compute_getter(grammar, name, query, getter)
      local child_grammar
      child_grammar = grammar.members[name]
      if not child_grammar then
         for member_name, member in pairs(grammar.members) do
            if child_grammar then break end
            if member.type == 'choice' then
               for case_name, case in pairs(member.choices) do
                  if child_grammar then break end
                  if case[name] then child_grammar = case[name] end
               end
            end
         end
      end
      if not child_grammar then
         error("Struct has no field named '"..name.."'.")
      end
      local id = normalize_id(name)
      local function child_getter(data)
         local struct = getter(data)
         local child = struct[id]
         if child == nil then
            error("Struct instance has no field named '"..name.."'.")
         end
         return child
      end
      return handle_query(child_grammar, query, child_getter)
   end
   local getter, grammar = function(data) return data end, grammar
   for _, elt in ipairs(parse_path(path_string)) do
      -- All non-leaves of the path tree must be structs.
      if grammar.type ~= 'struct' then error("Invalid path.") end
      getter, grammar = compute_getter(grammar, elt.name, elt.query, getter)
   end
   return getter, grammar
end
resolver = util.memoize(resolver)

local function printer_for_grammar(grammar, path, format, print_default)
   local getter, subgrammar = resolver(grammar, path)
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

local function printer_for_schema(schema, path, is_config, format,
                                  print_default)
   local grammar = data.data_grammar_from_schema(schema, is_config)
   return printer_for_grammar(grammar, path, format, print_default)
end

function printer_for_schema_by_name(schema_name, path, is_config, format,
                                    print_default)
   local schema = schema.load_schema_by_name(schema_name)
   return printer_for_schema(schema, path, is_config, format, print_default)
end
printer_for_schema_by_name = util.memoize(printer_for_schema_by_name)

local function parser_for_grammar(grammar, path)
   local getter, subgrammar = resolver(grammar, path)
   return data.data_parser_from_grammar(subgrammar)
end

local function parser_for_schema(schema, path)
   local grammar = data.config_grammar_from_schema(schema)
   return parser_for_grammar(grammar, path)
end

function parser_for_schema_by_name(schema_name, path)
   return parser_for_schema(schema.load_schema_by_name(schema_name), path)
end
parser_for_schema_by_name = util.memoize(parser_for_schema_by_name)

local function setter_for_grammar(grammar, path)
   if path == "/" then
      return function(config, subconfig) return subconfig end
   end
   local head, tail = lib.dirname(path), lib.basename(path)
   local tail_path = parse_path(tail)
   local tail_name, query = tail_path[1].name, tail_path[1].query
   if lib.equal(query, {}) then
      -- No query; the simple case.
      local getter, grammar = resolver(grammar, head)
      assert(grammar.type == 'struct')
      local tail_id = data.normalize_id(tail_name)
      return function(config, subconfig)
         getter(config)[tail_id] = subconfig
         return config
      end
   end

   -- Otherwise the path ends in a query; it must denote an array or
   -- table item.
   local getter, grammar = resolver(grammar, head..'/'..tail_name)
   if grammar.type == 'array' then
      local idx = prepare_array_lookup(query)
      return function(config, subconfig)
         local array = getter(config)
         assert(idx <= #array)
         array[idx] = subconfig
         return config
      end
   elseif grammar.type == 'table' then
      local key = prepare_table_lookup(grammar.keys, grammar.key_ctype, query)
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

local function setter_for_schema(schema, path)
   local grammar = data.config_grammar_from_schema(schema)
   return setter_for_grammar(grammar, path)
end

function setter_for_schema_by_name(schema_name, path)
   return setter_for_schema(schema.load_schema_by_name(schema_name), path)
end
setter_for_schema_by_name = util.memoize(setter_for_schema_by_name)

local function adder_for_grammar(grammar, path)
   local top_grammar = grammar
   local getter, grammar = resolver(grammar, path)
   if grammar.type == 'array' then
      if grammar.ctype then
         -- It's an FFI array; have to create a fresh one, sadly.
         local setter = setter_for_grammar(top_grammar, path)
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

local function adder_for_schema(schema, path)
   local grammar = data.config_grammar_from_schema(schema)
   return adder_for_grammar(grammar, path)
end

function adder_for_schema_by_name (schema_name, path)
   return adder_for_schema(schema.load_schema_by_name(schema_name), path)
end
adder_for_schema_by_name = util.memoize(adder_for_schema_by_name)

local function remover_for_grammar(grammar, path)
   local top_grammar = grammar
   local head, tail = lib.dirname(path), lib.basename(path)
   local tail_path = parse_path(tail)
   local tail_name, query = tail_path[1].name, tail_path[1].query
   local head_and_tail_name = head..'/'..tail_name
   local getter, grammar = resolver(grammar, head_and_tail_name)
   if grammar.type == 'array' then
      if grammar.ctype then
         -- It's an FFI array; have to create a fresh one, sadly.
         local idx = prepare_array_lookup(query)
         local setter = setter_for_grammar(top_grammar, head_and_tail_name)
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
      local key = prepare_table_lookup(grammar.keys, grammar.key_ctype, query)
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

local function remover_for_schema(schema, path)
   local grammar = data.config_grammar_from_schema(schema)
   return remover_for_grammar(grammar, path)
end

function remover_for_schema_by_name (schema_name, path)
   return remover_for_schema(schema.load_schema_by_name(schema_name), path)
end
remover_for_schema_by_name = util.memoize(remover_for_schema_by_name)

function selftest()
   print("selftest: lib.yang.path_data")
   local mem = require('lib.stream.mem')
   local schema_src = [[module snabb-simple-router {
      namespace snabb:simple-router;
      prefix simple-router;

      import ietf-inet-types {prefix inet;}

      leaf active { type boolean; default true; }
      leaf-list blocked-ips { type inet:ipv4-address; }

      container routes {
         list route {
            key addr;
            leaf addr { type inet:ipv4-address; mandatory true; }
            leaf port { type uint8 { range 0..11; } mandatory true; }
         }
      }}]]

   local scm = schema.load_schema(schema_src, "xpath-test")
   local grammar = data.config_grammar_from_schema(scm)

   -- Test resolving a key to a path.
   local data_src = mem.open_input_string [[
      active true;

      blocked-ips 8.8.8.8;
      blocked-ips 8.8.4.4;

      routes {
         route { addr 1.2.3.4; port 2; }
         route { addr 2.3.4.5; port 2; }
         route { addr 255.255.255.255; port 7; }
      }
   ]]

   local d = data.load_config_for_schema(scm, data_src)

   -- Try resolving a path in a list (ctable).
   local getter = resolver(grammar, "/routes/route[addr=1.2.3.4]/port")
   assert(getter(d) == 2)

   local getter = resolver(grammar, "/routes/route[addr=255.255.255.255]/port")
   assert(getter(d) == 7)

   -- Try resolving a leaf-list
   local getter = resolver(grammar, "/blocked-ips[position()=1]")
   assert(getter(d) == util.ipv4_pton("8.8.8.8"))

   -- Try resolving a path for a list (non-ctable)
   local fruit_schema_src = [[module fruit-bowl {
      namespace snabb:fruit-bowl;
      prefix simple-router;

      import ietf-inet-types {prefix inet;}

      container bowl {
         list fruit {
            key name;
            leaf name { type string; mandatory true; }
            leaf rating { type uint8 { range 0..10; } mandatory true; }
            choice C {
               case A { leaf AA { type string; } }
               case B { leaf BB { type string; } }
            }
         }
      }}]]
   local fruit_data_src = mem.open_input_string [[
      bowl {
         fruit { name "banana"; rating 10; }
         fruit { name "pear"; rating 2; }
         fruit { name "apple"; rating 6; }
         fruit { name "kumquat"; rating 6; AA aa; }
         fruit { name "tangerine"; rating 6; BB bb; }
      }
   ]]

   local fruit_scm = schema.load_schema(fruit_schema_src, "xpath-fruit-test")
   local fruit_prod = data.config_grammar_from_schema(fruit_scm)
   local fruit_data = data.load_config_for_schema(fruit_scm, fruit_data_src)

   local getter = resolver(fruit_prod, "/bowl/fruit[name=banana]/rating")
   assert(getter(fruit_data) == 10)

   local getter = resolver(fruit_prod, "/bowl/fruit[name=apple]/rating")
   assert(getter(fruit_data) == 6)

   local getter = resolver(fruit_prod, "/bowl/fruit[name=kumquat]/AA")
   assert(getter(fruit_data) == 'aa')

   local getter = resolver(fruit_prod, "/bowl/fruit[name=tangerine]/BB")
   assert(getter(fruit_data) == 'bb')

   print("selftest: ok")
end
