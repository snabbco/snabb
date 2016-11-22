-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- This module can be used to parse a path based on a yang schema (or its
-- derivative grammar) and produce a lua table which is a native lua way
-- of representing a path. The path provided is a subset of XPath supporting
-- named keys such as [addr=1.2.3.4] and also basic positional querying
-- for arrays e.g [position()=1] for the first element.
--
-- The structure of the path is dependent on the type the node is. The
-- conversions are as follows:
--
-- Scalar fields:
--    A lua string of the member name
-- Struct fields:
--    A lua string of the member name
-- Array fields:
--    This is a table which has a "name" property specifying member
--    name and a "key" field which is a 1 based integer to specify the
--    position in the array.
-- Table fields:
--    This is a table which has a "name" property specifying member
--    name and has a "keys" (not key) property which is either:
--       - A string representing the key if the table is string keyed.
--       - A lua table with corrisponding leaf names as the key and the
--         value as the value.
module(..., package.seeall)

local ffi = require("ffi")
local equal = require("core.lib").equal
local schemalib = require("lib.yang.schema")
local datalib = require("lib.yang.data")
local valuelib = require("lib.yang.value")
local util = require("lib.yang.util")
local normalize_id = datalib.normalize_id

local function table_keys(t)
   local ret = {}
   for k, v in pairs(t) do table.insert(ret, k) end
   return ret
end

local function extract_parts(fragment)
   local rtn = {query={}}
   rtn.name = string.match(fragment, "([^%[]+)")
   for k,v in string.gmatch(fragment, "%[([^=]+)=([^%]]+)%]") do
      rtn.query[k] = v
   end
   return rtn
end

-- Finds the grammar node for a fragment in a given grammar.
local function extract_grammar_node(grammar, name)
   local handlers = {}
   function handlers.struct () return grammar.members[name] end
   function handlers.table ()
      if grammar.keys[name] == nil then
         return grammar.values[name]
      else
         return grammar.keys[name]
      end
   end
   return assert(assert(handlers[grammar.type], grammar.type)(), name)
end

-- Converts an XPath path to a lua array consisting of path componants.
-- A path component can then be resolved on a yang data tree:
function convert_path(grammar, path)
   local handlers = {}
   function handlers.scalar(grammar, fragment)
      return {name=fragment.name, grammar=grammar}
   end
   function handlers.struct(grammar, fragment)
      return {name=fragment.name, grammar=grammar}
   end
   function handlers.table(grammar, fragment)
      return {name=fragment.name, keys=fragment.query, grammar=grammar}
   end
   function handlers.array(grammar, fragment)
      local position = fragment.query["position()"]
      return {name=fragment.name, key=tonumber(position), grammar=grammar}
   end
   local function handle(grammar, fragment)
      return assert(handlers[grammar.type], grammar.type)(grammar, fragment)
   end

   local ret = {}
   local node = grammar
   if path:sub(1, 1) == "/" then path = path:sub(2) end -- remove leading /
   if path:sub(-1) == "/" then path = path:sub(1, -2) end -- remove trailing /
   for element in path:split("/") do
      local parts = extract_parts(element)
      node = extract_grammar_node(node, parts.name)
      local luapath = handle(node, parts)
      table.insert(ret, luapath)
   end
   return ret
end

function parse_path(path)
   local ret = {}
   for element in path:split("/") do
      if element ~= '' then table.insert(ret, extract_parts(element)) end
   end
   return ret
end

-- Returns a resolver for a paticular schema and *lua* path.
function resolver(grammar, path)
   local function prepare_table_key(keys, ctype, query)
      local static_key = ctype and datalib.typeof(ctype)() or {}
      for k,_ in pairs(query) do
         if not keys[k] then error("'"..key_name.."' is not a table key") end
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
      local key = prepare_table_key(grammar.keys, grammar.key_ctype, query)
      local child_grammar = {type="struct", members=grammar.values,
                             ctype=grammar.value_ctype}
      local child_getter = compute_table_getter(grammar, key, getter)
      return child_getter, child_grammar
   end
   local function handle_array_query(grammar, query, getter)
      if not equal(table_keys(query), {"position()"}) then
         error("Arrays can only be indexed by position.")
      end
      local idx = tonumber(query["position()"])
      if idx < 1 or idx ~= math.floor(idx) then
         error("Arrays can only be indexed by positive integers.")
      end
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
      local child_grammar = grammar.members[name]
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
   for _, elt in ipairs(path) do
      -- All non-leaves of the path tree must be structs.
      if grammar.type ~= 'struct' then error("Invalid path.") end
      getter, grammar = compute_getter(grammar, elt.name, elt.query, getter)
   end
   return getter, grammar
end

-- Loads a module and converts the rest of the path.
function load_from_path(path)
   -- First extract and load the module name then load it.
   local module_name, path = next_element(path)
   local scm = schemalib.load_schema_by_name(module_name)
   local grammar = datalib.data_grammar_from_schema(scm)
   return module_name, convert_path(grammar.members, path)
end

function selftest()
   print("selftest: lib.yang.path")
   local schema_src = [[module snabb-simple-router {
      namespace snabb:simple-router;
      prefix simple-router;

      import ietf-inet-types {prefix inet;}

      leaf active { type boolean; default true; }
      leaf-list blocked-ips { type inet:ipv4-address; }

      container routes {
         presence true;
         list route {
            key addr;
            leaf addr { type inet:ipv4-address; mandatory true; }
            leaf port { type uint8 { range 0..11; } mandatory true; }
         }
      }}]]

   local scm = schemalib.load_schema(schema_src, "xpath-test")
   local grammar = datalib.data_grammar_from_schema(scm)

   -- Test path to lua path.
   local path = convert_path(grammar,"/routes/route[addr=1.2.3.4]/port")

   assert(path[1].name == "routes")
   assert(path[2].name == "route")
   assert(path[2].keys)
   assert(path[2].keys["addr"] == "1.2.3.4")
   assert(path[3].name == "port")

   local path = convert_path(grammar, "/blocked-ips[position()=4]/")
   assert(path[1].name == "blocked-ips")
   assert(path[1].key == 4)

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

   local data = datalib.load_data_for_schema(scm, data_src)

   -- Try resolving a path in a list (ctable).
   local path = parse_path("/routes/route[addr=1.2.3.4]/port")
   assert(resolver(grammar, path)(data) == 2)

   local path = parse_path("/routes/route[addr=255.255.255.255]/port")
   assert(resolver(grammar, path)(data) == 7)

   -- Try resolving a leaf-list
   local path = parse_path("/blocked-ips[position()=1]")
   assert(resolver(grammar, path)(data) == util.ipv4_pton("8.8.8.8"))

   -- Try resolving a path for a list (non-ctable)
   local fruit_schema_src = [[module fruit-bowl {
      namespace snabb:fruit-bowl;
      prefix simple-router;

      import ietf-inet-types {prefix inet;}

      container bowl {
         presence true;
         list fruit {
            key name;
            leaf name { type string; mandatory true; }
            leaf rating { type uint8 { range 0..10; } mandatory true; }
         }
      }}]]
   local fruit_data_src = [[
      bowl {
         fruit { name "banana"; rating 10; }
         fruit { name "pear"; rating 2; }
         fruit { name "apple"; rating 6; }
      }
   ]]

   local fruit_scm = schemalib.load_schema(fruit_schema_src, "xpath-fruit-test")
   local fruit_prod = datalib.data_grammar_from_schema(fruit_scm)
   local fruit_data = datalib.load_data_for_schema(fruit_scm, fruit_data_src)

   local path = parse_path("/bowl/fruit[name=banana]/rating")
   assert(resolver(fruit_prod, path)(fruit_data) == 10)

   local path = parse_path("/bowl/fruit[name=apple]/rating")
   assert(resolver(fruit_prod, path)(fruit_data) == 6)
   print("selftest: ok")
end
