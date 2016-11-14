-- -- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- This module can be used to parse a path based on a yang schema (or it's
-- derivative grammar) and produce a lua table which is a native lua way
-- of representing a path. The path provided is a subset of XPath supporting
-- named keys such as [addr=1.2.3.4] and also basic positional querying
-- for arrays e.g [position()=1] for the first element.
--
-- The structure of the path is dependent on the type the node is, the
-- conversions are as follows:
--
-- Scala fields:
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

local schema = require("lib.yang.schema")
local data = require("lib.yang.data")

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
      k, v = pairs(tree.keys)()
      if v.argument_type.primitive_type == "string" then
	 return {name=fragment.name, key=fragment.query[k]}, tree
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
-- A path compent can then be resolved on a yang data tree:

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


-- Loads a module and converts the rest of the path.
function load_from_path(path)
   -- First extract and load the module name then load it.
   module_name, path = next_element(fragment)
   scm = schema.load_schema_by_name(module_name)
   grammar = data.data_grammar_for_schema(scm)
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

   local schemalib = require("lib.yang.schema")
   local datalib = require("lib.yang.data")
   local schema = schemalib.load_schema(schema_src, "xpath-test")
   local grammar = datalib.data_grammar_from_schema(schema)

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
end
