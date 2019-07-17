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

local equal = require("core.lib").equal
local datalib = require("lib.yang.data")
local normalize_id = datalib.normalize_id

local function table_keys(t)
   local ret = {}
   for k, v in pairs(t) do table.insert(ret, k) end
   return ret
end

local syntax_error = function (str, pos)
   local header = "Syntax error in "
   io.stderr:write(header..str.."\n")
   io.stderr:write(string.rep(" ", #header + pos-1))
   io.stderr:write("^\n")
   os.exit(1)
end

local function extract_parts (fragment)
   local rtn = {query={}}
   local pos
   function consume (char)
      if fragment:sub(pos, pos) ~= char then
         syntax_error(fragment, pos)
      end
      pos = pos + 1
   end
   function eol ()
      return pos > #fragment
   end
   function token ()
      local ret, new_pos = fragment:match("([^=%]]+)()", pos)
      if not ret then
         syntax_error(fragment, pos)
      end
      pos = new_pos
      return ret
   end
   rtn.name, pos = string.match(fragment, "([^%[]+)()")
   while not eol() do
      consume('[', pos)
      local k = token()
      consume('=')
      local v = token()
      consume(']')
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
   function handlers.choice ()
      for case_name, case in pairs(grammar.choices) do
         if case[name] ~= nil then return case[name] end
      end
   end
   return assert(assert(handlers[grammar.type], grammar.type)(), name)
end

-- Converts an XPath path to a lua array consisting of path componants.
-- A path component can then be resolved on a yang data tree:
function convert_path(grammar, path)
   local path = normalize_path(path)
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

   if path == "/" then return {} end

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

function parse_path (path)
   local depth = 0
   local t, token = {}, ''
   local function insert_token ()
      table.insert(t, token)
      token = ''
   end
   for i=1,#path do
      local c = path:sub(i, i)
      if depth == 0 and c == '/' then
         if #token > 0 then
            insert_token()
         end
      else
         token = token..c
         if c == '[' then depth = depth + 1 end
         if c == ']' then
            depth = depth - 1
            if depth == 0 and path:sub(i+1, i+1) ~= '[' then
               insert_token()
            end
         end
      end
   end
   insert_token()

   local ret = {}
   for _, element in ipairs(t) do
      if element ~= '' then table.insert(ret, extract_parts(element)) end
   end
   return ret
end

function normalize_path(path)
   local ret = {}
   for _,part in ipairs(parse_path(path)) do
      local str = part.name
      local keys = table_keys(part.query)
      table.sort(keys)
      for _,k in ipairs(keys) do str = str..'['..k..'='..part.query[k]..']' end
      table.insert(ret, str)
   end
   return '/'..table.concat(ret, '/')
end

function selftest()
   print("selftest: lib.yang.path")
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

   assert(normalize_path('') == '/')
   assert(normalize_path('//') == '/')
   assert(normalize_path('/') == '/')
   assert(normalize_path('//foo//bar//') == '/foo/bar')
   assert(normalize_path('//foo[b=1][c=2]//bar//') == '/foo[b=1][c=2]/bar')
   assert(normalize_path('//foo[c=1][b=2]//bar//') == '/foo[b=2][c=1]/bar')

   assert(extract_parts('//foo[b=1]'))

   parse_path('/alarms/alarm-list/alarm'..
              '[resource=alarms/alarm-list/alarm/related-alarm/resource]'..
              '[alarm-type-id=/alarms/alarm-list/alarm/related-alarm/alarm-type-id]')

   print("selftest: ok")
end
