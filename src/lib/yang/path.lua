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
local schemalib = require("lib.yang.schema")
local datalib = require("lib.yang.data")
local valuelib = require("lib.yang.value")
local util = require("lib.yang.util")
local normalize_id = datalib.normalize_id

local function extract_parts(fragment)
   local rtn = {query={}}
   rtn.name = string.match(fragment, "([^%[]+)")
   for k,v in string.gmatch(fragment, "%[([^=]+)=([^%]]+)%]") do
      rtn.query[k] = v
   end
   return rtn
end

local handlers = {}
function handlers.scalar(grammar, fragment)
   return {name=fragment.name, grammar=grammar} end
function handlers.struct(grammar, fragment)
   return {name=fragment.name, keys=fragment.query, grammar=grammar}
end
function handlers.table(grammar, fragment)
   return {name=fragment.name, keys=fragment.query, grammar=grammar}
end
function handlers.array(grammar, fragment)
   local position = fragment.query["position()"]
   return {name=fragment.name, key=tonumber(position), grammar=grammar}
end
function handle(grammar, fragment)
   return assert(handlers[grammar.type], grammar.type)(grammar, fragment)
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

-- Returns a resolver for a paticular schema and *lua* path.
function resolver(path)
   local handlers = {}
   local function handle(data, path)
      if #path == 0 then return data end
      local head = table.remove(path, 1)
      local handler = assert(handlers[head.grammar.type], head.grammar.type)
      return handler(head, data, path)
   end
   function handlers.table(head, data, path)
      -- The list can either be a ctable or a plain old lua table, if it's the
      -- ctable then it requires some more work to retrive the data.
      local data = data[normalize_id(head.name)]
      if #head.grammar.keys > 1 then
         error("Multiple key values are not supported!")
      end
      if head.grammar.key_ctype then
         -- It's a ctable and we need to prepare the key so we can lookup the
         -- pointer to the entry and then convert the values back to lua.
         local keyname = next(head.keys)
         local ptype = head.grammar.keys[keyname].argument_type.primitive_type
         local kparser = valuelib.types[ptype].parse
         local key = kparser(head.keys[keyname])
         local ckey = ffi.new(head.grammar.key_ctype)
         ckey[keyname] = key

         data = data:lookup_ptr(ckey).value
      else
         data = data[normalize_id(head.keys[next(head.keys)])]
      end
      return handle(data, path)
   end
   function handlers.struct(head, data, path)
      data = data[normalize_id(head.name)]
      return handle(data, path)
   end
   function handlers.array(head, data, path)
      data = data[normalize_id(head.name)][head.key]
      return handle(data, path)
   end
   function handlers.scalar(head, data, path)
      if #path ~= 0 then error("Paths can't go beyond leaves.") end
      return data[normalize_id(head.name)]
   end
   return function (data)
      return handle(data, path)
   end
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
   print("selftest: lib.yang.xpath")
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
   local path = convert_path(grammar,"/routes/route[addr=1.2.3.4]/port")
   assert(resolver(path)(data) == 2)

   local path = convert_path(grammar,"/routes/route[addr=255.255.255.255]/port")
   assert(resolver(path)(data) == 7)

   -- Try resolving a leaf-list
   local path = convert_path(grammar,"/blocked-ips[position()=1]")
   assert(resolver(path)(data) == util.ipv4_pton("8.8.8.8"))

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

   local path = convert_path(fruit_prod, "/bowl/fruit[name=banana]/rating")
   assert(resolver(path)(fruit_data) == 10)

   local path = convert_path(fruit_prod, "/bowl/fruit[name=apple]/rating")
   assert(resolver(path)(fruit_data) == 6)
end
