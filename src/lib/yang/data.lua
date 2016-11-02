-- Use of this source code is governed by the Apache 2.0 license; see
-- COPYING.
module(..., package.seeall)

local parse_string = require("lib.yang.parser").parse_string
local schema = require("lib.yang.schema")
local util = require("lib.yang.util")
local value = require("lib.yang.value")

function normalize_id(id)
   return id:gsub('[^%w_]', '_')
end

function data_grammar_from_schema(schema)
   local function struct_ctype(members) end
   local function value_ctype(type) end
   local handlers = {}
   local function visit(node)
      local handler = handlers[node.kind]
      if handler then return handler(node) end
      return {}
   end
   local function visit_body(node)
      local ret = {}
      for id,node in pairs(node.body) do
         for keyword,node in pairs(visit(node)) do
            assert(not ret[keyword], 'duplicate identifier: '..keyword)
            assert(not ret[normalize_id(keyword)],
                   'duplicate identifier: '..normalize_id(keyword))
            ret[keyword] = node
         end
      end
      return ret
   end
   function handlers.container(node)
      local members = visit_body(node)
      if not node.presence then return members end
      return {[node.id]={type='struct', members=members,
                         ctype=struct_ctype(members)}}
   end
   handlers['leaf-list'] = function(node)
      return {[node.id]={type='array', element_type=node.type,
                         ctype=value_ctype(node.type)}}
   end
   function handlers.list(node)
      local members=visit_body(node)
      local keys, values = {}, {}
      for k in node.key:split(' +') do keys[k] = assert(members[k]) end
      for k,v in pairs(members) do
         if not keys[k] then values[k] = v end
      end
      return {[node.id]={type='table', keys=keys, values=values,
                         key_ctype=struct_ctype(keys),
                         value_ctype=struct_ctype(values)}}
   end
   function handlers.leaf(node)
      return {[node.id]={type='scalar', argument_type=node.type,
                         default=node.default, mandatory=node.mandatory,
                         ctype=value_ctype(node.type)}}
   end
   local members = visit_body(schema)
   return {type="struct", members=members, ctype=struct_ctype(members)}
end

local function integer_type(min, max)
   return function(str, k)
      return util.tointeger(str, k, min, max)
   end
end

-- FIXME :)
local function range_validator(range, f) return f end
local function length_validator(range, f) return f end
local function pattern_validator(range, f) return f end
local function bit_validator(range, f) return f end
local function enum_validator(range, f) return f end

local function value_parser(typ)
   local prim = typ.primitive_type
   local parse = assert(value.types[prim], prim).parse
   local function validate(val) end
   validate = range_validator(typ.range, validate)
   validate = length_validator(typ.length, validate)
   validate = pattern_validator(typ.pattern, validate)
   validate = bit_validator(typ.bit, validate)
   validate = enum_validator(typ.enum, validate)
   -- TODO: union, require-instance.
   return function(str, k)
      local val = parse(str, k)
      validate(val)
      return val
   end
end

local function assert_scalar(node, keyword, opts)
   assert(node.argument or (opts and opts.allow_empty_argument),
          'missing argument for "'..keyword..'"')
   assert(not node.statements, 'unexpected sub-parameters for "'..keyword..'"')
end

local function assert_compound(node, keyword)
   assert(not node.argument, 'argument unexpected for "'..keyword..'"')
   assert(node.statements,
          'missing brace-delimited sub-parameters for "'..keyword..'"')
end

local function assert_not_duplicate(out, keyword)
   assert(not out, 'duplicate parameter: '..keyword)
end

local function struct_parser(keyword, members, ctype)
   local function init() return nil end
   local function parse1(node)
      assert_compound(node, keyword)
      local ret = {}
      for k,sub in pairs(members) do ret[normalize_id(k)] = sub.init() end
      for _,node in ipairs(node.statements) do
         local sub = assert(members[node.keyword],
                            'unrecognized parameter: '..node.keyword)
         local id = normalize_id(node.keyword)
         ret[id] = sub.parse(node, ret[id])
      end
      for k,sub in pairs(members) do
         local id = normalize_id(k)
         ret[id] = sub.finish(ret[id])
      end
      return ret
   end
   local function parse(node, out)
      assert_not_duplicate(out, keyword)
      return parse1(node)
   end
   local struct_t = ctype and ffi.typeof(ctype)
   local function finish(out)
      -- FIXME check mandatory values.
      if struct_t then return struct_t(out) else return out end
   end
   return {init=init, parse=parse, finish=finish}
end

local function array_parser(keyword, element_type, ctype)
   local function init() return {} end
   local parsev = value_parser(element_type)
   local function parse1(node)
      assert_scalar(node, keyword)
      return parsev(node.argument, k)
   end
   local function parse(node, out)
      table.insert(out, parse1(node))
      return out
   end
   local array_t = ctype and ffi.typeof('$[?]', ffi.typeof(ctype))
   local function finish(out)
      -- FIXME check min-elements
      if array_t then return array_t(out) else return out end
   end
   return {init=init, parse=parse, finish=finish}
end

local function scalar_parser(keyword, argument_type, default, mandatory)
   local function init() return nil end
   local parsev = value_parser(argument_type)
   local function parse1(node)
      assert_scalar(node, keyword, {allow_empty_argument=true})
      return parsev(node.argument, keyword)
   end
   local function parse(node, out)
      assert_not_duplicate(out, keyword)
      return parse1(node)
   end
   local function finish(out)
      if out ~= nil then return out end
      if default then return parse1(default) end
      if mandatory then error('missing scalar value: '..k) end
   end
   return {init=init, parse=parse, finish=finish}
end

-- Simple temporary associative array until we get the various Table
-- kinds working.
function make_assoc()
   local assoc = {}
   function assoc:get_entry(k)
      assert(type(k) ~= 'table', 'multi-key lookup unimplemented')
      for _,entry in ipairs(self) do
         for _,v in pairs(entry.key) do
            if v == k then return entry end
         end
      end
      error('not found: '..k)
   end
   function assoc:get_key(k) return self:get_entry(k).key end
   function assoc:get_value(k) return self:get_entry(k).value end
   function assoc:add(k, v, check)
      if check then assert(not self:get_entry(k)) end
      table.insert(self, {key=k, value=v})
   end
   return assoc
end

local function table_parser(keyword, keys, values, key_ctype, value_ctype)
   local members = {}
   for k,v in pairs(keys) do members[k] = v end
   for k,v in pairs(values) do members[k] = v end
   local parser = struct_parser(keyword, members)
   local key_t = key_ctype and ffi.typeof(key_ctype)
   local value_t = value_ctype and ffi.typeof(value_ctype)
   local init
   if key_t and value_t then
      function init()
         return ctable.new({ key_type=key_t, value_type=value_t })
      end
   elseif key_t or value_t then
      error('mixed table types currently unimplemented')
   else
      function init() return make_assoc() end
   end
   local function parse1(node)
      assert_compound(node, keyword)
      return parser.finish(parser.parse(node, parser.init()))
   end
   local function parse(node, assoc)
      local struct = parse1(node)
      local key, value = {}, {}
      if key_t then key = key_t() end
      if value_t then value = value_t() end
      for k,v in pairs(struct) do
         local id = normalize_id(k)
         if keys[k] then key[id] = v else value[id] = v end
      end
      assoc:add(key, value)
      return assoc
   end
   local function finish(assoc)
      return assoc
   end
   return {init=init, parse=parse, finish=finish}
end

function data_parser_from_schema(schema)
   return data_parser_from_grammar(data_grammar_from_schema(schema))
end

function data_parser_from_grammar(production)
   local handlers = {}
   local function visit1(keyword, production)
      return assert(handlers[production.type])(keyword, production)
   end
   local function visitn(productions)
      local ret = {}
      for keyword,production in pairs(productions) do
         ret[keyword] = visit1(keyword, production)
      end
      return ret
   end
   function handlers.struct(keyword, production)
      local members = visitn(production.members)
      return struct_parser(keyword, members, production.ctype)
   end
   function handlers.array(keyword, production)
      return array_parser(keyword, production.element_type, production.ctype)
   end
   function handlers.table(keyword, production)
      local keys, values = visitn(production.keys), visitn(production.values)
      return table_parser(keyword, keys, values, production.key_ctype,
                          production.value_ctype)
   end
   function handlers.scalar(keyword, production)
      return scalar_parser(keyword, production.argument_type,
                           production.default, production.mandatory)
   end

   local parser = visit1('(top level)', production)
   return function(str, filename)
      local node = {statements=parse_string(str, filename)}
      return parser.finish(parser.parse(node, parser.init()))
   end
end

function load_data_for_schema(schema, str, filename)
   return data_parser_from_schema(schema)(str, filename)
end

function load_data_for_schema_by_name(schema_name, str, filename)
   local schema = schema.load_schema_by_name(schema_name)
   return load_data_for_schema(schema, str, filename)
end

function selftest()
   local test_schema = schema.load_schema([[module fruit {
      namespace "urn:testing:fruit";
      prefix "fruit";
      import ietf-inet-types {prefix inet; }
      grouping fruit {
         leaf name {
            type string;
            mandatory true;
         }
         leaf score {
            type uint8 { range 0..10; }
            mandatory true;
         }
         leaf tree-grown { type boolean; }
      }

      container fruit-bowl {
         presence true;
         leaf description { type string; }
         list contents { uses fruit; key name; }
      }
      leaf addr {
         description "internet of fruit";
         type inet:ipv4-address;
      }
   }]])

   local data = load_data_for_schema(test_schema, [[
     fruit-bowl {
       description 'ohai';
       contents { name foo; score 7; }
       contents { name bar; score 8; }
       contents { name baz; score 9; tree-grown true; }
     }
     addr 1.2.3.4;
   ]])
   assert(data.fruit_bowl.description == 'ohai')
   local contents = data.fruit_bowl.contents
   assert(contents:get_entry('foo').key.name == 'foo')
   assert(contents:get_entry('foo').value.score == 7)
   assert(contents:get_key('foo').name == 'foo')
   assert(contents:get_value('foo').score == 7)
   assert(contents:get_value('foo').tree_grown == nil)
   assert(contents:get_key('bar').name == 'bar')
   assert(contents:get_value('bar').score == 8)
   assert(contents:get_value('bar').tree_grown == nil)
   assert(contents:get_key('baz').name == 'baz')
   assert(contents:get_value('baz').score == 9)
   assert(contents:get_value('baz').tree_grown == true)
   assert(require('lib.protocol.ipv4'):ntop(data.addr) == '1.2.3.4')
end
