-- Use of this source code is governed by the Apache 2.0 license; see
-- COPYING.
module(..., package.seeall)

local ffi = require("ffi")
local parser = require("lib.yang.parser")
local schema = require("lib.yang.schema2")

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

local function struct_parser(members, k)
   local function init() return nil end
   local function parse1(node)
      assert(not node.argument, 'argument unexpected for struct type: '..k)
      assert(node.statements, 'missing statements for struct type: '..k)
      local ret = {}
      for k,sub in pairs(members) do ret[k] = sub.init() end
      for _,node in ipairs(node.statements) do
         local sub = assert(members[node.keyword],
                            'unrecognized keyword: '..node.keyword)
         ret[node.keyword] = sub.parse(node, ret[node.keyword])
      end
      for k,sub in pairs(members) do ret[k] = sub.finish(ret[k]) end
      return ret
   end
   local function parse(node, out)
      if out then error('duplicate struct: '..k) end
      return parse1(node)
   end
   local function finish(out)
      -- FIXME check mandatory
      return out
   end
   return {init=init, parse=parse, finish=finish}
end

local function array_parser(typ, k)
   local function init() return {} end
   local parsev = value_parser(typ)
   local function parse1(node)
      assert(node.argument, 'argument expected for array type: '..k)
      assert(not node.statements, 'unexpected statements for array type: '..k)
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

local function scalar_parser(typ, default, mandatory, k)
   local function init() return nil end
   local parsev = value_parser(typ)
   local function parse1(node)
      assert(not node.statements, 'unexpected statements for scalar type: '..k)
      return parsev(node.argument, k)
   end
   local function parse(node, out)
      assert(not out, 'duplicate scalar config value: '..k)
      return parse1(node)
   end
   local function finish(out)
      if out ~= nil then return out end
      if default then return parse1(default) end
      if mandatory then error('missing scalar value: '..k) end
   end
   return {init=init, parse=parse, finish=finish}
end

local function table_parser(keystr, members, k)
   -- This is a temporary lookup until we get the various Table kinds
   -- working.
   local function lookup(out, k)
      for _,v in ipairs(out) do
         if v[keystr] == k then return v end
      end
      error('not found: '..k)
   end
   local function init() return {lookup=lookup} end
   local parser = struct_parser(members, k)
   local function parse1(node)
      assert(not node.argument, 'argument unexpected for table type: '..k)
      assert(node.statements, 'expected statements for table type: '..k)
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
   function handlers.module(node)
   end
   function handlers.container(node)
      if not node.presence then return visit_body(node) end
      return {[node.id]=struct_parser(visit_body(node), node.id)}
   end
   handlers['leaf-list'] = function(node)
      return {[node.id]=array_parser(node.type, node.id)}
   end
   function handlers.list(node)
      return {[node.id]=table_parser(node.key, visit_body(node), node.id)}
   end
   function handlers.leaf(node)
      return {[node.id]=scalar_parser(node.type, node.default, node.mandatory,
node.id)}
   end

   local parser = struct_parser(visit_body(schema), '(top level)')
   return function(stmtlist)
      return parser.finish(parser.parse({statements=stmtlist}, parser.init()))
   end
end

function selftest()
   local test_schema = [[module fruit {
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
   }]]

   local schema = schema.load_schema(test_schema)
   local parse = data_parser_from_schema(schema)
   local data = parse(parser.parse_string([[
     fruit-bowl {
       description 'ohai';
       contents { name foo; score 7; }
       contents { name bar; score 8; }
       contents { name baz; score 9; tree-grown true; }
     }
   ]]))
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
