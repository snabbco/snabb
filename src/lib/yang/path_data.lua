-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local equal = require("core.lib").equal
local datalib = require("lib.yang.data")
local valuelib = require("lib.yang.value")
local pathlib = require("lib.yang.path")
local util = require("lib.yang.util")
local normalize_id = datalib.normalize_id

local function table_keys(t)
   local ret = {}
   for k, v in pairs(t) do table.insert(ret, k) end
   return ret
end

function prepare_array_lookup(query)
   if not equal(table_keys(query), {"position()"}) then
      error("Arrays can only be indexed by position.")
   end
   local idx = tonumber(query["position()"])
   if idx < 1 or idx ~= math.floor(idx) then
      error("Arrays can only be indexed by positive integers.")
   end
   return idx
end

function prepare_table_lookup(keys, ctype, query)
   local static_key = ctype and datalib.typeof(ctype)() or {}
   for k,_ in pairs(query) do
      if not keys[k] then error("'"..k.."' is not a table key") end
   end
   for k,grammar in pairs(keys) do
      local v = query[k] or grammar.default
      if v == nil then
         error("Table query missing required key '"..k.."'")
      end
      local key_primitive_type = grammar.argument_type.primitive_type
      local parser = valuelib.types[key_primitive_type].parse
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
            if equal(k, key) then return v end
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
      if equal(table_keys(query), {}) then return getter, grammar end
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
   for _, elt in ipairs(pathlib.parse_path(path_string)) do
      -- All non-leaves of the path tree must be structs.
      if grammar.type ~= 'struct' then error("Invalid path.") end
      getter, grammar = compute_getter(grammar, elt.name, elt.query, getter)
   end
   return getter, grammar
end
resolver = util.memoize(resolver)

function selftest()
   print("selftest: lib.yang.path_data")
   local schemalib = require("lib.yang.schema")
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

   local scm = schemalib.load_schema(schema_src, "xpath-test")
   local grammar = datalib.config_grammar_from_schema(scm)

   -- Test resolving a key to a path.
   local data_src = [[
      active true;

      blocked-ips 8.8.8.8;
      blocked-ips 8.8.4.4;

      routes {
         route { addr 1.2.3.4; port 2; }
         route { addr 2.3.4.5; port 2; }
         route { addr 255.255.255.255; port 7; }
      }
   ]]

   local data = datalib.load_config_for_schema(scm, data_src)

   -- Try resolving a path in a list (ctable).
   local getter = resolver(grammar, "/routes/route[addr=1.2.3.4]/port")
   assert(getter(data) == 2)

   local getter = resolver(grammar, "/routes/route[addr=255.255.255.255]/port")
   assert(getter(data) == 7)

   -- Try resolving a leaf-list
   local getter = resolver(grammar, "/blocked-ips[position()=1]")
   assert(getter(data) == util.ipv4_pton("8.8.8.8"))

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
   local fruit_data_src = [[
      bowl {
         fruit { name "banana"; rating 10; }
         fruit { name "pear"; rating 2; }
         fruit { name "apple"; rating 6; }
         fruit { name "kumquat"; rating 6; AA aa; }
         fruit { name "tangerine"; rating 6; BB bb; }
      }
   ]]

   local fruit_scm = schemalib.load_schema(fruit_schema_src, "xpath-fruit-test")
   local fruit_prod = datalib.config_grammar_from_schema(fruit_scm)
   local fruit_data = datalib.load_config_for_schema(fruit_scm, fruit_data_src)

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
