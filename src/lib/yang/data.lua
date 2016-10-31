-- Use of this source code is governed by the Apache 2.0 license; see
-- COPYING.
module(..., package.seeall)

local ffi = require("ffi")
local parse_string = require("lib.yang.parser").parse_string
local schema = require("lib.yang.schema")

function data_grammar_from_schema(schema)
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
            ret[keyword] = node
         end
      end
      return ret
   end
   function handlers.container(node)
      if not node.presence then return visit_body(node) end
      return {[node.id]={type='struct', members=visit_body(node)}}
   end
   handlers['leaf-list'] = function(node)
      return {[node.id]={type='array', element_type=node.type}}
   end
   function handlers.list(node)
      local keys = {}
      for key in node.key:split(' +') do table.insert(keys, key) end
      return {[node.id]={type='table', keys=keys, members=visit_body(node)}}
   end
   function handlers.leaf(node)
      return {[node.id]={type='scalar', argument_type=node.type,
                         default=node.default, mandatory=node.mandatory}}
   end
   return {type="struct", members=visit_body(schema)}
end

ffi.cdef([[
unsigned long long strtoull (const char *nptr, const char **endptr, int base);
]])

local function integer_type(min, max)
   return function(str, k)
      local str = assert(str, 'missing value for '..k)
      local start = 1
      local is_negative
      local base = 10
      if str:match('^-') then start, is_negative = 2, true
      elseif str:match('^+') then start = 2 end
      if str:match('^0x', start) then base, start = 16, start + 2
      elseif str:match('^0', start) then base = 8 end
      str = str:lower()
      local function check(test)
         return assert(test, 'invalid numeric value for '..k..': '..str)
      end
      check(start <= str:len())
      -- FIXME: check that res did not overflow the 64-bit number
      local res = ffi.C.strtoull(str:sub(start), nil, base)
      if is_negative then
         res = ffi.new('int64_t[1]', -1*res)[0]
         check(res <= 0)
      end
      check(min <= res and res <= max)
      if tonumber(res) == res then return tonumber(res) end
      return res
   end
end

local primitive_parsers = {}

primitive_parsers.int8 = integer_type(-0xf0, 0x7f)
primitive_parsers.int16 = integer_type(-0xf000, 0x7fff)
primitive_parsers.int32 = integer_type(-0xf000000, 0x7fffffff)
primitive_parsers.int64 = integer_type(-0xf00000000000000LL, 0x7fffffffffffffffLL)
primitive_parsers.uint8 = integer_type(0, 0xff)
primitive_parsers.uint16 = integer_type(0, 0xffff)
primitive_parsers.uint32 = integer_type(0, 0xffffffff)
primitive_parsers.uint64 = integer_type(0, 0xffffffffffffffffULL)
function primitive_parsers.binary(str, k)
   error('unimplemented: binary')
   return str
end
function primitive_parsers.bits(str, k)
   error('unimplemented: bits')
end
function primitive_parsers.boolean(str, k)
   local str = assert(str, 'missing value for '..k)
   if str == 'true' then return true end
   if str == 'false' then return false end
   error('bad boolean value: '..str)
end
function primitive_parsers.decimal64(str, k)
   error('unimplemented: decimal64')
end
function primitive_parsers.empty(str, k)
   assert(not str, 'unexpected value for '..k)
   return true
end
function primitive_parsers.enumeration(str, k)
   return assert(str, 'missing value for '..k)
end
function primitive_parsers.identityref(str, k)
   error('unimplemented: identityref')
end
primitive_parsers['instance-identifier'] = function(str, k)
   error('unimplemented: instance-identifier')
end
function primitive_parsers.leafref(str, k)
   error('unimplemented: leafref')
end
function primitive_parsers.string(str, k)
   return assert(str, 'missing value for '..k)
end
function primitive_parsers.union(str, k)
   error('unimplemented: union')
end

-- FIXME :)
local function range_validator(range, f) return f end
local function length_validator(range, f) return f end
local function pattern_validator(range, f) return f end
local function bit_validator(range, f) return f end
local function enum_validator(range, f) return f end

local function value_parser(typ)
   local prim = typ.base_type
   -- FIXME: perhaps cache the primitive type on all type nodes.
   while type(prim) ~= 'string' do prim = prim.base_type end
   local parse = assert(primitive_parsers[prim], prim)
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

local function struct_parser(keyword, members)
   local function init() return nil end
   local function parse1(node)
      assert_compound(node, keyword)
      local ret = {}
      for k,sub in pairs(members) do ret[k] = sub.init() end
      for _,node in ipairs(node.statements) do
         local sub = assert(members[node.keyword],
                            'unrecognized parameter: '..node.keyword)
         ret[node.keyword] = sub.parse(node, ret[node.keyword])
      end
      for k,sub in pairs(members) do ret[k] = sub.finish(ret[k]) end
      return ret
   end
   local function parse(node, out)
      assert_not_duplicate(out, keyword)
      return parse1(node)
   end
   local function finish(out)
      -- FIXME check mandatory
      return out
   end
   return {init=init, parse=parse, finish=finish}
end

local function array_parser(keyword, element_type)
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
   local function finish(out)
      -- FIXME check min-elements
      return out
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

local function table_parser(keyword, keys, members)
   -- This is a temporary lookup until we get the various Table kinds
   -- working.
   local function lookup(out, k)
      for _,v in ipairs(out) do
         if #keys == 1 then
            if v[keys[1]] == k then return v end
         end
      end
      error('not found: '..k)
   end
   local function init() return {lookup=lookup} end
   local parser = struct_parser(keyword, members)
   local function parse1(node)
      assert_compound(node, keyword)
      return parser.finish(parser.parse(node, parser.init()))
   end
   local function parse(node, out)
      -- TODO: tease out key from value, add to associative array
      table.insert(out, parse1(node))
      return out
   end
   local function finish(out)
      -- FIXME check min-elements
      return out
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
      return struct_parser(keyword, visitn(production.members))
   end
   function handlers.array(keyword, production)
      return array_parser(keyword, production.element_type)
   end
   function handlers.table(keyword, production)
      return table_parser(keyword, production.keys, visitn(production.members))
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
   }]])

   local data = load_data_for_schema(test_schema, [[
     fruit-bowl {
       description 'ohai';
       contents { name foo; score 7; }
       contents { name bar; score 8; }
       contents { name baz; score 9; tree-grown true; }
     }
   ]])
   assert(data['fruit-bowl'].description == 'ohai')
   assert(data['fruit-bowl'].contents:lookup('foo').name == 'foo')
   assert(data['fruit-bowl'].contents:lookup('foo').score == 7)
   assert(data['fruit-bowl'].contents:lookup('foo')['tree-grown'] == nil)
   assert(data['fruit-bowl'].contents:lookup('bar').name == 'bar')
   assert(data['fruit-bowl'].contents:lookup('bar').score == 8)
   assert(data['fruit-bowl'].contents:lookup('bar')['tree-grown'] == nil)
   assert(data['fruit-bowl'].contents:lookup('baz').name == 'baz')
   assert(data['fruit-bowl'].contents:lookup('baz').score == 9)
   assert(data['fruit-bowl'].contents:lookup('baz')['tree-grown'] == true)
end
