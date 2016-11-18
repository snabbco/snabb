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
local lib = require("core.lib")
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
function handlers.scalar(fragment, tree)
   return fragment.name, tree
end
function handlers.struct(fragment, tree)
   return fragment.name, tree.members
end
function handlers.table(fragment, tree)
   if #tree.keys == 1 then
      -- Check if the key is a string based key
      if tree.string_key then
         return {name=fragment.name, key=tree.string_key}, tree
      end
   else
      return {name=fragment.name, keys=fragment.query}, tree
   end
end
function handlers.array(fragment, tree)
   local position = fragment.query["position()"]
   return {name=fragment.name, key=tonumber(position)}
end
function handle(node_type, fragment, tree)
   return assert(handlers[node_type], node_type)(fragment, tree)
end

-- Gets the next item in the path returning the element and the remaining
-- path fragment. For example "router.routes.route" will return "router"
-- and "routes.route". If the end is reached it'll return nil.
function next_element(path)
   return string.match(path, "([^/]+)/?(.*)")
end

-- Converts an XPath path to a lua array consisting of path componants.
-- A path component can then be resolved on a yang data tree:

local function convert_path(path, grammar)
   -- Extract head, check type and dispatch to handler.
   local head, tail = next_element(path)
   local parts = extract_parts(head)
   local err = "Invalid path: "..parts.name
   local node
   if grammar.type == "table" then
      if grammar.keys[head] == nil then
         node = assert(grammar.values[parts.name], err)
      else
         node = grammar.keys[head]
      end
   else
      node = assert(grammar[parts.name], err)
   end
   local element, node = handle(node.type, parts, node)
   if tail ~= "" then
      local rtn = convert_path(tail, node)
      table.insert(rtn, 1, element)
      return rtn
   else
      return {element}
   end
end

function resolve(schema, data, path)
   local handlers = {}
   local function handle(scm, prod, data, path)
      if #path == 0 then return data end
      return assert(handlers[scm.kind], scm.kind)(scm, prod, data, path)
   end
   function handlers.list(scm, prod, data, path)
      local head = table.remove(path, 1)
      -- The list can either be a ctable or a plain old lua table, if it's the
      -- ctable then it requires some more work to retrive the data.
      local prod = prod.members[head.name]
      local data = data[normalize_id(head.name)]
      if #prod.keys > 1 then error("Multiple key values are not supported!") end
      if prod.key_ctype then
         -- It's a ctable and we need to prepare the key so we can lookup the
         -- pointer to the entry and then convert the values back to lua.
         local kparser = valuelib.types[scm.body[scm.key].primitive_type].parse
         local key = kparser(head.keys[scm.key])
         local ckey = ffi.new(prod.key_ctype)
         ckey[scm.key] = key

         data = data:lookup_ptr(ckey).value
      else
         data = data[normalize_id(head.keys[scm.key])]
      end

      if #path == 0 then return data end
      local peek = path[1]
      if type(peek) == "table" then peek = peek.name end
      scm = scm.body[peek]
      prod = prod.values[peek]
      return handle(scm, prod, data, path)
   end
   function handlers.container(scm, prod, data, path)
      local head = table.remove(path, 1)
      prod = prod.members[head]
      data = data[normalize_id(head)]
      if #path == 0 then return data end
      local peek = path[1]
      if type(peek) == "string" then scm = scm.body[peek]
      else scm = scm.body[peek.name] end
      return handle(scm, prod, data, path)
   end
   handlers["leaf-list"] = function (scm, prod, data, path)
      local head = table.remove(path, 1)
      if #path ~= 0 then error("Paths can't go beyond leaf-lists.") end
      return data[normalize_id(head.name)][head.key]
   end
   function handlers.leaf(scm, prod, data, path)
      local head = table.remove(path, 1)
      if #path ~= 0 then error("Paths can't go beyond leaves.") end
      return data[normalize_id(head)]
   end
   function handlers.module(scm, prod, data, path)
      local peek = path[1]
      if type(peek) == "table" then peek = peek.name end
      scm = scm.body[peek]
      return handle(scm, prod, data, path)
   end

   local schema = lib.deepcopy(schema)
   local path = lib.deepcopy(path)
   local data = lib.deepcopy(data)
   local grammar = datalib.data_grammar_from_schema(schema)
   return handle(schema, grammar, data, path)
end

-- Loads a module and converts the rest of the path.
function load_from_path(path)
   -- First extract and load the module name then load it.
   local module_name, path = next_element(path)
   local scm = schema.load_schema_by_name(module_name)
   local grammar = data.data_grammar_from_schema(scm)
   return module_name, convert_path(path, grammar.members)
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
   local path = convert_path("/routes/route[addr=1.2.3.4]/port", grammar.members)

   assert(path[1] == "routes")
   assert(path[2].name == "route")
   assert(path[2].keys)
   assert(path[2].keys["addr"] == "1.2.3.4")
   assert(path[3] == "port")

   local path = convert_path("/blocked-ips[position()=4]/", grammar.members)
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
   local path = convert_path("/routes/route[addr=1.2.3.4]/port",
      grammar.members)
   assert(resolve(scm, data, path) == 2)

   local path = convert_path("/routes/route[addr=255.255.255.255]/port",
      grammar.members)
   assert(resolve(scm, data, path) == 7)

   -- Try resolving a leaf-list
   local path = convert_path("/blocked-ips[position()=1]",
      grammar.members)
   assert(resolve(scm, data, path) == util.ipv4_pton("8.8.8.8"))

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

   local path = convert_path("/bowl/fruit[name=banana]/rating",
      fruit_prod.members)
   assert(resolve(fruit_scm, fruit_data, path) == 10)

   local path = convert_path("/bowl/fruit[name=apple]/rating",
      fruit_prod.members)
   assert(resolve(fruit_scm, fruit_data, path) == 6)
end
