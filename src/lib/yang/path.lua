-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- This module can be used to parse a path based on a yang schema (or its
-- derivative grammar) and produce a lua table which is a native lua way
-- of representing a path. The path provided is a subset of XPath supporting
-- named keys such as [addr=1.2.3.4] and also basic positional querying
-- for arrays e.g [position()=1] for the first element.
module(..., package.seeall)

local valuelib = require("lib.yang.value")
local datalib = require("lib.yang.data")
local normalize_id = datalib.normalize_id
local lib = require("core.lib")


local function syntax_error(str, pos)
   error("Syntax error in:\n"
      ..str.."\n"
      ..string.rep(" ", pos-1).."^\n")
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
   local function expand_choices (members)
      for _, member in pairs(members) do
         if member.type == 'choice' then
            local node = extract_grammar_node(member, name)
            if node then return node end
         end
      end
   end
   local handlers = {}
   function handlers.struct (node)
      if node.members[name] then return node.members[name] end
      return expand_choices(node.members)
   end
   function handlers.list (node)
      if node.keys[name] then return node.keys[name] end
      if node.values[name] then return node.values[name] end
      return expand_choices(node.values)
   end
   function handlers.choice (node)
      for _, case in pairs(node.choices) do
         if case[name] then return case[name] end
         local node = expand_choices(case)
         if node then return node end
      end
   end
   function handlers.scalar ()
      error("Invalid path: trying to access '"..name.."' in scalar.")
   end
   function handlers.array ()
      error("Invalid path: trying to access '"..name.."' in leaf-list.")
   end
   -- rpc
   function handlers.sequence (node)
      if node.members[name] then return node.members[name] end
   end
   local node = assert(handlers[grammar.type], grammar.type)(grammar)
   return node or error("Invalid path: '"..name.."' is not in schema.")
end

-- Converts an XPath path to a lua array consisting of path components.
local function parse_path1 (path)
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

   local ret = {relative = not path:match("^/")}
   for _, element in ipairs(t) do
      if element ~= '' then table.insert(ret, extract_parts(element)) end
   end
   return ret
end

local function parse_query(grammar, query)
   if grammar.type == 'array' then
      local idx
      for key, value in pairs(query) do
         if key == 'position()' then
            idx = tonumber(value)
         else
            error("Invalid query: leaf-list can only be indexed by position.")
         end
      end
      if (not idx) or idx < 1 or idx ~= math.floor(idx) then
         error("Invalid query: leaf-list can only be indexed by positive integers.")
      end
      return idx
   elseif grammar.type == 'list' then
      if not grammar.list.has_key then
         error("Invalid query: list has no key.")
      end
      local key = {}
      for k,_ in pairs(query) do
         if not grammar.keys[k] then
            error("Invalid query:'"..k.."' is not a list key.")
         end
      end
      for k,grammar in pairs(grammar.keys) do
         local v = query[k] or grammar.default
         if v == nil then
            error("Invalid query: missing required key '"..k.."'")
         end
         local key_primitive_type = grammar.argument_type.primitive_type
         local parser = valuelib.types[key_primitive_type].parse
         key[normalize_id(k)] = parser(v, 'path query value')
      end
      return key
   else
      error("Invalid query: can only query list or leaf-list.")
   end
end

function parse_path(path, grammar)
   if type(path) == 'string' then
      path = parse_path1(path)
   end
   if grammar then
      for _, part in ipairs(path) do
         grammar = extract_grammar_node(grammar, part.name)
         part.grammar = grammar
         for _ in pairs(part.query) do
            part.key = parse_query(grammar, part.query)
            break
         end
      end
   end
   return path
end

local function unparse_query(grammar, key)
   if grammar.type == 'array' then
      return {['position()']=tonumber(key)}
   elseif grammar.type == 'list' then
      if not grammar.list.has_key then
         error("Invalid key: list has no key.")
      end
      local query = {}
      for k,grammar in pairs(grammar.keys) do
         local key_primitive_type = grammar.argument_type.primitive_type
         local tostring = valuelib.types[key_primitive_type].tostring
         local id = normalize_id(k)
         if key[id] then
            query[k] = tostring(key[id])
         elseif grammar.default then
            query[k] = grammar.default
         else
            error("Invalid key: missing required key '"..k.."'")
         end
      end
      return query
   else
      error("Invalid key: can only query list or leaf-list.")
   end
end

function unparse_path(path, grammar)
   path = lib.deepcopy(path)
   for _, part in ipairs(path) do
      grammar = extract_grammar_node(grammar, part.name)
      part.grammar = grammar
      if part.key then
         part.query = unparse_query(grammar, part.key)
      end
   end
   return path
end

function normalize_path(path, grammar)
   path = parse_path(path, grammar)
   local ret = {}
   for _,part in ipairs(path) do
      local str = part.name
      local keys = {}
      for key in pairs(part.query) do
         table.insert(keys, key)
      end
      table.sort(keys)
      for _,k in ipairs(keys) do str = str..'['..k..'='..part.query[k]..']' end
      table.insert(ret, str)
   end
   return ((path.relative and '') or '/')..table.concat(ret, '/')
end

function parse_relative_path(path, node_path, grammar)
   path = parse_path(path)
   if not path.relative then
      return parse_path(path, grammar)
   end
   node_path = parse_path(node_path, grammar)
   assert(not node_path.relative, "node_path has to be absolute.")
   local apath = {relative=false}
   for _, part in ipairs(node_path) do
      table.insert(apath, part)
   end
   for i, part in ipairs(path) do
      if part.name == '.' or part.name == 'current()' then
         assert(i==1, "Invalid path: '"..part.name"' has to be first component.")
      elseif part.name == '..' then
         assert(#apath >= 1, "Invalid path: attempt to traverse up root (/..).")
         table.remove(apath, #apath)
      else
         table.insert(apath, part)
      end
   end
   return parse_path(apath, grammar)
end

function selftest()
   print("selftest: lib.yang.path")
   local util = require("lib.yang.util")
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
   local path = parse_path("/routes/route[addr=1.2.3.4]/port", grammar)

   assert(path[1].name == "routes")
   assert(path[2].name == "route")
   assert(path[2].query.addr == "1.2.3.4")
   assert(path[2].key.addr == util.ipv4_pton("1.2.3.4"))
   assert(path[3].name == "port")

   local path = parse_path("/blocked-ips[position()=4]/", grammar)
   assert(path[1].name == "blocked-ips")
   assert(path[1].query['position()'] == "4")
   assert(path[1].key == 4)

   assert(normalize_path('') == '')
   assert(normalize_path('//') == '/')
   assert(normalize_path('/') == '/')
   assert(normalize_path('//foo//bar//') == '/foo/bar')
   assert(normalize_path('//foo[b=1][c=2]//bar//') == '/foo[b=1][c=2]/bar')
   assert(normalize_path('//foo[c=1][b=2]//bar//') == '/foo[b=2][c=1]/bar')

   local path = 
      parse_path('/alarms/alarm-list/alarm'..
                 '[resource=alarms/alarm-list/alarm/related-alarm/resource]'..
                 '[alarm-type-id=/alarms/alarm-list/alarm/related-alarm/alarm-type-id]')
   assert(#path == 3)
   assert(path[3].name == 'alarm')
   assert(path[3].query.resource == "alarms/alarm-list/alarm/related-alarm/resource")
   assert(path[3].query['alarm-type-id'] == "/alarms/alarm-list/alarm/related-alarm/alarm-type-id")

   print("selftest: ok")
end
