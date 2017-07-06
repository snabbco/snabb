-- Use of this source code is governed by the Apache 2.0 license; see
-- COPYING.
module(..., package.seeall)

local parser_mod = require("lib.yang.parser")
local schema = require("lib.yang.schema")
local util = require("lib.yang.util")
local value = require("lib.yang.value")
local ffi = require("ffi")
local ctable = require('lib.ctable')
local cltable = require('lib.cltable')

function normalize_id(id)
   return id:gsub('[^%w_]', '_')
end

-- Helper for parsing C type declarations.
local function parse_type(str, start, is_member)
   local function err(msg, pos)
      io.stderr:write('ERROR: While parsing type:\n')
      io.stderr:write('ERROR:   '..str..'\n')
      io.stderr:write('ERROR:   '..string.rep(' ', pos - 1)..'^\n')
      io.stderr:write('ERROR: '..msg..'\n')
      error(msg, 2)
   end
   local function assert_match(str, pat, pos, what)
      local ret = { str:match(pat, pos) }
      if not ret[1] then err('bad '..what, pos) end
      return unpack(ret)
   end
   local t, array, member, pos
   -- See if it's a struct.
   t, pos = str:match('^%s*(struct%s*%b{})%s*()', start)
   -- Otherwise it might be a scalar.
   if not t then t, pos = str:match('^%s*([%a_][%w_]*)%s*()', start) end
   -- We don't do unions currently.
   if not t then err('invalid type', start) end
   -- If we're parsing a struct or union member, get the name.
   if is_member then
      member, pos = assert_match(str, '^([%a_][%w_]*)%s*()', pos, 'member name')
   end
   -- Parse off the array suffix, if any.
   if str:match('^%[', pos) then
      array, pos = assert_match(str, '^(%b[])%s*()', pos, 'array component')
   end
   if is_member then
      -- Members should have a trailing semicolon.
      pos = assert_match(str, '^;%s*()', pos, 'semicolon')
   else
      -- Nonmembers should parse to the end of the string.
      assert_match(str, '^()$', pos, 'suffix')
   end
   return t, array, member, pos
end

-- We want structural typing, not nominal typing, for Yang data.  The
-- "foo" member in "struct { struct { uint16 a; } foo; }" should not
-- have a unique type; we want to be able to instantiate a "struct {
-- uint16 a; }" and get a compatible value.  To do this, we parse out
-- nested "struct" types and only ever make one FFI type for each
-- compatible struct kind.  The user-facing interface is the "typeof"
-- function below; the "compile_type" helper handles nesting.
--
-- It would be possible to avoid this complexity by having the grammar
-- generate something other than a string "ctype" representation, but
-- then we don't have a type name to serialize into binary data.  We
-- might as well embrace the type strings.
local function compile_type(name)
   local function maybe_array_type(t, array)
      -- If ARRAY is something like "[10]", make a corresponding type.
      -- Otherwise just return T.
      if array then return ffi.typeof('$'..array, t) end
      return t
   end
   local parsed, array = parse_type(name, 1, false)
   local ret
   if parsed:match('^struct[%s{]') then
      -- It's a struct type; parse out the members and rebuild.
      local struct_type = 'struct { '
      local struct_type_args = {}
      local function add_member(member_type, member_name)
         struct_type = struct_type..'$ '..member_name..'; '
         table.insert(struct_type_args, member_type)
      end
      -- Loop from initial "struct {" to final "}".
      local pos = assert(parsed:match('^struct%s*{%s*()'))
      while not parsed:match('^}$', pos) do
         local mtype, mname, marray
         mtype, marray, mname, pos = parse_type(parsed, pos, true)
         -- Recurse on mtype by calling the caching "typeof" defined
         -- below.
         add_member(maybe_array_type(typeof(mtype), marray), mname)
      end
      struct_type = struct_type..'}'
      ret = ffi.typeof(struct_type, unpack(struct_type_args))
   else
      -- Otherwise the type is already structural and we can just use
      -- ffi.typeof.
      ret = ffi.typeof(parsed)
   end
   return maybe_array_type(ret, array)
end

local type_cache = {}
function typeof(name)
   assert(type(name) == 'string')
   if not type_cache[name] then type_cache[name] = compile_type(name) end
   return type_cache[name]
end

-- If a "list" node has one key that is string-valued, we will represent
-- instances of that node as normal Lua tables where the key is the
-- table key and the value does not contain the key.
local function table_string_key(keys)
   local string_key = nil
   for k,v in pairs(keys) do
      if v.type ~= 'scalar' then return nil end
      if v.argument_type.primitive_type ~= 'string' then return nil end
      if string_key ~= nil then return nil end
      string_key = k
   end
   return string_key
end

-- We need to properly support unions.  It's a big FIXME!  As an
-- intermediate step, we pick the first type in the union.  Terrible.
local function elide_unions(t)
   while t.primitive_type == 'union' do t = t.union[1] end
   return t
end

function data_grammar_from_schema(schema)
   local function struct_ctype(members)
      local member_names = {}
      for k,v in pairs(members) do
         if not v.ctype then return nil end
         table.insert(member_names, k)
      end
      table.sort(member_names)
      local ctype = 'struct { '
      for _,k in ipairs(member_names) do
         -- Separate the array suffix off of things like "uint8_t[4]".
         local head, tail = members[k].ctype:match('^([^%[]*)(.*)$')
         ctype = ctype..head..' '..normalize_id(k)..tail..'; '
      end
      ctype = ctype..'}'
      return ctype
   end
   local function value_ctype(type)
      -- Note that not all primitive types have ctypes.
      return assert(value.types[assert(type.primitive_type)]).ctype
   end
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
      return {[node.id]={type='struct', members=members,
                         ctype=struct_ctype(members)}}
   end
   function handlers.choice(node)
      local choices = {}
      for choice, n in pairs(node.body) do
         choices[choice] = visit_body(n)
      end
      return {[node.id] = {type="choice", default=node.default, mandatory=node.mandatory,
                           choices=choices}}
   end
   handlers['leaf-list'] = function(node)
      local t = elide_unions(node.type)
      return {[node.id]={type='array', element_type=t,
                         ctype=value_ctype(t)}}
   end
   function handlers.list(node)
      local members=visit_body(node)
      local keys, values = {}, {}
      if node.key then
         for k in node.key:split(' +') do keys[k] = assert(members[k], node.key) end
      end
      for k,v in pairs(members) do
         if not keys[k] then values[k] = v end
      end
      return {[node.id]={type='table', keys=keys, values=values,
                         string_key=table_string_key(keys),
                         key_ctype=struct_ctype(keys),
                         value_ctype=struct_ctype(values)}}
   end
   function handlers.leaf(node)
      local ctype
      local t = elide_unions(node.type)
      if node.default or node.mandatory then ctype=value_ctype(t) end
      return {[node.id]={type='scalar', argument_type=t,
                         default=node.default, mandatory=node.mandatory,
                         ctype=ctype}}
   end
   local members = visit_body(schema)
   return {type="struct", members=members, ctype=struct_ctype(members)}
end
data_grammar_from_schema = util.memoize(data_grammar_from_schema)

function rpc_grammar_from_schema(schema)
   local grammar = {}
   for _,prop in ipairs({'input', 'output'}) do
      grammar[prop] = { type="sequence", members={} }
      for k,rpc in pairs(schema.rpcs) do
         local node = rpc[prop]
         if node then
            grammar[prop].members[k] = data_grammar_from_schema(node)
         else
            grammar[prop].members[k] = {type="struct", members={}}
         end
      end
   end
   return grammar
end

function rpc_input_grammar_from_schema(schema)
   return rpc_grammar_from_schema(schema).input
end

function rpc_output_grammar_from_schema(schema)
   return rpc_grammar_from_schema(schema).output
end

local function integer_type(min, max)
   return function(str, k)
      return util.tointeger(str, k, min, max)
   end
end

-- FIXME
local function range_validator(range, f) return f end
local function length_validator(range, f) return f end
local function pattern_validator(range, f) return f end
local function bit_validator(range, f) return f end
local function enum_validator(enums, f)
   if not enums then return f end
   return function (val)
      if not enums[val] then
         error('enumeration '..val..' is not a valid value')
      end
      return val
   end
end
local function identityref_validator(bases, default_prefix, f)
   if not default_prefix then return f end
   return function(val)
      if not val:match(':') then val = default_prefix..":"..val end
      local identity = schema.lookup_identity(val)
      for _, base in ipairs(bases) do
         if not schema.identity_is_instance_of(identity, base) then
            error('identity '..val..' not an instance of '..base)
         end
      end
      return val
   end
end

local function value_parser(typ)
   local prim = typ.primitive_type
   local parse = assert(value.types[prim], prim).parse
   local validate = function(val) return val end
   local function enums (node)
      return node.primitive_type == 'enumeration' and node.enums or nil
   end
   validate = range_validator(typ.range, validate)
   validate = length_validator(typ.length, validate)
   validate = pattern_validator(typ.pattern, validate)
   validate = bit_validator(typ.bit, validate)
   validate = enum_validator(enums(typ), validate)
   validate = identityref_validator(typ.bases, typ.default_prefix, validate)
   -- TODO: union, require-instance.
   return function(str, k)
      return validate(parse(str, k))
   end
end

local function struct_parser(keyword, members, ctype)
   local keys = {}
   for k,v in pairs(members) do table.insert(keys, k) end
   local function init() return nil end
   local function parse1(P)
      local ret = {}
      local expanded_members = {}
      for _,k in ipairs(keys) do
         if members[k].represents then
            -- Choice fields don't include the name of the choice block in the data. They
            -- need to be able to provide the parser for the leaves it represents.
            local member_parser = members[k].stateful_parser()
            for _, node in pairs(members[k].represents()) do
               -- Choice fields need to keep state around as they're called multiple times
               -- and need to do some validation to comply with spec.
               expanded_members[node] = member_parser
            end
         else
            ret[normalize_id(k)] = members[k].init()
            expanded_members[k] = members[k]
         end
      end
      P:skip_whitespace()
      P:consume("{")
      P:skip_whitespace()
      while not P:check("}") do
         local k = P:parse_identifier()
         if k == '' then P:error("Expected a keyword") end
         -- Scalar/array parser responsible for requiring whitespace
         -- after keyword.  Struct/table don't need it as they have
         -- braces.
         local sub = assert(expanded_members[k], 'unrecognized parameter: '..k)
         local id = normalize_id(k)
         ret[id] = sub.parse(P, ret[id], k)
         P:skip_whitespace()
      end
      for k,_ in pairs(expanded_members) do
         local id = normalize_id(k)
         ret[id] = expanded_members[k].finish(ret[id], k)
      end
      return ret
   end
   local function parse(P, out)
      if out ~= nil then P:error('duplicate parameter: '..keyword) end
      return parse1(P)
   end
   local struct_t = ctype and typeof(ctype)
   local function finish(out, leaf)
     -- FIXME check mandatory values.
      if struct_t then
        local ret
        if out == nil then ret = struct_t()
        else ret = struct_t(out) end
        return ret
      else
        return out
      end
   end
   return {init=init, parse=parse, finish=finish}
end

local function array_parser(keyword, element_type, ctype)
   local function init() return {} end
   local parsev = value_parser(element_type)
   local function parse1(P)
      P:consume_whitespace()
      local str = P:parse_string()
      P:skip_whitespace()
      P:consume(";")
      return parsev(str, keyword)
   end
   local function parse(P, out)
      table.insert(out, parse1(P))
      return out
   end
   local elt_t = ctype and typeof(ctype)
   local array_t = ctype and ffi.typeof('$[?]', elt_t)
   local function finish(out)
      -- FIXME check min-elements
      if array_t then
         out = util.ffi_array(array_t(#out, out), elt_t)
      end
      return out
   end
   return {init=init, parse=parse, finish=finish}
end

local function scalar_parser(keyword, argument_type, default, mandatory)
   local function init() return nil end
   local parsev = value_parser(argument_type)
   local function parse1(P)
      local maybe_str
      if argument_type.primitive_type ~= 'empty' then
         P:consume_whitespace()
         maybe_str = P:parse_string()
      end
      P:skip_whitespace()
      P:consume(";")
      return parsev(maybe_str, keyword)
   end
   local function parse(P, out)
      if out ~= nil then P:error('duplicate parameter: '..keyword) end
      return parse1(P)
   end
   local function finish(out)
      if out ~= nil then return out end
      if default then return parsev(default, keyword) end
      if mandatory then error('missing scalar value: '..keyword) end
   end
   return {init=init, parse=parse, finish=finish}
end

function choice_parser(keyword, choices, members, default, mandatory)
   -- Create a table matching the leaf names to the case statement
   local choice_map = {}
   for case, choice in pairs(choices) do
      for leaf in pairs(choice) do
         choice_map[leaf] = case
      end
   end

   local function stateful_parser()
      -- This holds the value of the chosen case block so we're able to prevent mixing of
      -- using different leaves from different case statements.
      local chosen

      local function init() return {} end
      local function parse(P, out, k)
         if chosen and choice_map[k] ~= chosen then
            error("Only one choice set can exist at one time: "..keyword)
         else
            chosen = choice_map[k]
         end
         return members[chosen][k].parse(P, members[chosen][k].init(), k)
      end

      -- This holds a copy of all the nodes so we know when we've hit the last one.
      local function finish(out, k)
         if out ~= nil then return out end
         if mandatory and chosen == nil then error("missing choice value: "..keyword) end
         if default and default == choice_map[k] then
            return members[default][k].finish()
         end
      end
      return {init=init, parse=parse, finish=finish}
   end
   local function represents()
      local nodes = {}
      for name, _ in pairs(choice_map) do table.insert(nodes, name) end
      return nodes
   end
   return {represents=represents, stateful_parser=stateful_parser}
end

local function ctable_builder(key_t, value_t)
   local res = ctable.new({ key_type=key_t, value_type=value_t,
                            max_occupancy_rate = 0.4 })
   local builder = {}
   -- Uncomment for progress counters.
   -- local counter = 0
   function builder:add(key, value)
      -- counter = counter + 1
      -- if counter % 1000 == 0 then print('ctable add', counter) end
      res:add(key, value)
   end
   function builder:finish() return res end
   return builder
end

local function string_keyed_table_builder(string_key)
   local res = {}
   local builder = {}
   function builder:add(key, value)
      local str = assert(key[string_key])
      assert(res[str] == nil, 'duplicate key: '..str)
      res[str] = value
   end
   function builder:finish() return res end
   return builder
end

local function cltable_builder(key_t)
   local res = cltable.new({ key_type=key_t })
   local builder = {}
   function builder:add(key, value)
      assert(res[key] == nil, 'duplicate key')
      res[key] = value
   end
   function builder:finish() return res end
   return builder
end

local function ltable_builder()
   local res = {}
   local builder = {}
   function builder:add(key, value) res[key] = value end
   function builder:finish() return res end
   return builder
end

local function table_parser(keyword, keys, values, string_key, key_ctype,
                            value_ctype)
   local members = {}
   for k,v in pairs(keys) do members[k] = v end
   for k,v in pairs(values) do members[k] = v end
   local parser = struct_parser(keyword, members)
   local key_t = key_ctype and typeof(key_ctype)
   local value_t = value_ctype and typeof(value_ctype)
   local init
   if key_t and value_t then
      function init() return ctable_builder(key_t, value_t) end
   elseif string_key then
      function init() return string_keyed_table_builder(string_key) end
   elseif key_t then
      function init() return cltable_builder(key_t) end
   else
      function init() return ltable_builder() end
   end
   local function parse1(P)
      return parser.finish(parser.parse(P, parser.init()))
   end
   local function parse(P, assoc)
      local struct = parse1(P)
      local key, value = {}, {}
      if key_t then key = key_t() end
      if value_t then value = value_t() end
      for k,_ in pairs(keys) do
         local id = normalize_id(k)
         key[id] = struct[id]
      end
      for k, v in pairs(struct) do
         local id = normalize_id(k)
         if keys[k] == nil then
            value[id] = struct[id]
         end
      end
      assoc:add(key, value)
      return assoc
   end
   local function finish(assoc)
      return assoc:finish()
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
      return table_parser(keyword, keys, values, production.string_key,
                          production.key_ctype, production.value_ctype)
   end
   function handlers.scalar(keyword, production)
      return scalar_parser(keyword, production.argument_type,
                           production.default, production.mandatory)
   end
   function handlers.choice(keyword, production)
      local members = {}
      for case, choice in pairs(production.choices) do members[case] = visitn(choice) end
      return choice_parser(keyword, production.choices, members,
                           production.default, production.mandatory)
   end

   local top_parsers = {}
   function top_parsers.struct(production)
      local struct_t = production.ctype and typeof(production.ctype)
      local members = visitn(production.members)
      return function(str, filename)
         local P = parser_mod.Parser.new(str, filename)
         local ret = {}
         for k,sub in pairs(members) do ret[normalize_id(k)] = sub.init() end
         while true do
            P:skip_whitespace()
            if P:is_eof() then break end
            local k = P:parse_identifier()
            if k == '' then P:error("Expected a keyword") end
            local sub = assert(members[k], 'unrecognized parameter: '..k)
            local id = normalize_id(k)
            ret[id] = sub.parse(P, ret[id], k)
         end
         for k,sub in pairs(members) do
            local id = normalize_id(k)
            ret[id] = sub.finish(ret[id])
         end
         if struct_t then return struct_t(ret) else return ret end
      end
   end
   function top_parsers.sequence(production)
      local members = visitn(production.members)
      return function(str, filename)
         local P = parser_mod.Parser.new(str, filename)
         local ret = {}
         while true do
            P:skip_whitespace()
            if P:is_eof() then break end
            local k = P:parse_identifier()
            P:consume_whitespace()
            local sub = assert(members[k], 'unrecognized rpc: '..k)
            local data = sub.finish(sub.parse(P, sub.init(), k))
            table.insert(ret, {id=k, data=data})
         end
         return ret
      end
   end
   function top_parsers.array(production)
      local parser = visit1('[bare array]', production)
      return function(str, filename)
         local P = parser_mod.Parser.new(str, filename)
         local out = parser.init()
         while true do
            P:skip_whitespace()
            if P:is_eof() then break end
            out = parser.parse(P, out)
         end
         return parser.finish(out)
      end
   end
   function top_parsers.table(production)
      local parser = visit1('[bare table]', production)
      return function(str, filename)
         local P = parser_mod.Parser.new(str, filename)
         local out = parser.init()
         while true do
            P:skip_whitespace()
            if P:is_eof() then break end
            out = parser.parse(P, out)
         end
         return parser.finish(out)
      end
   end
   function top_parsers.scalar(production)
      local parse = value_parser(production.argument_type)
      return function(str, filename)
         return parse(parser_mod.parse_string(str, filename), '[bare scalar]')
      end
   end
   return assert(top_parsers[production.type])(production)
end
data_parser_from_grammar = util.memoize(data_parser_from_grammar)

function load_data_for_schema(schema, str, filename)
   return data_parser_from_schema(schema)(str, filename)
end

function load_data_for_schema_by_name(schema_name, str, filename)
   local schema = schema.load_schema_by_name(schema_name)
   return load_data_for_schema(schema, str, filename)
end

function rpc_input_parser_from_schema(schema)
   return data_parser_from_grammar(rpc_input_grammar_from_schema(schema))
end

function rpc_output_parser_from_schema(schema)
   return data_parser_from_grammar(rpc_output_grammar_from_schema(schema))
end

local function encode_yang_string(str)
   if str:match("^[^%s;{}\"'/]*$") then return str end
   local out = {}
   table.insert(out, '"')
   for i=1,#str do
      local chr = str:sub(i,i)
      if chr == '\n' then
         table.insert(out, '\\n')
      elseif chr == '\t' then
         table.insert(out, '\\t')
      elseif chr == '"' or chr == '\\' then
         table.insert(out, '\\')
         table.insert(out, chr)
      else
         table.insert(out, chr)
      end
   end
   table.insert(out, '"')
   return table.concat(out)
end

local value_serializers = {}
local function value_serializer(typ)
   local prim = typ.primitive_type
   if value_serializers[prim] then return value_serializers[prim] end
   local tostring = assert(value.types[prim], prim).tostring
   local function serializer(val)
      return encode_yang_string(tostring(val))
   end
   value_serializers[prim] = serializer
   return serializer
end

function xpath_printer_from_grammar(production, print_default, root)
   if #root > 1 and root:sub(#root, #root) == '/' then
      root = root:sub(1, #root-1)
   end
   local handlers = {}
   local translators = {}
   local function printer(keyword, production, printers)
      return assert(handlers[production.type])(keyword, production, printers)
   end
   local function print_string(str, file)
      file:write(encode_yang_string(str))
   end
   local function print_keyword(k, file, path)
      path = path:sub(1, 1) ~= '[' and root..'/'..path or root..path
      file:write(path)
      print_string(k, file)
      file:write(' ')
   end
   local function body_printer(productions, order)
      -- Iterate over productions trying to translate to other statements. This
      -- is used for example in choice statements raising the lower statements
      -- in case blocks up to the level of the choice, in place of the choice.
      local translated = {}
      for keyword,production in pairs(productions) do
         local translator = translators[production.type]
         if translator ~= nil then
            local statements = translator(keyword, production)
            for k,v in pairs(statements) do translated[k] = v end
         else
            translated[keyword] = production
         end
      end
      productions = translated
      if not order then
         order = {}
         for k,_ in pairs(productions) do table.insert(order, k) end
         table.sort(order)
      end
      local printers = {}
      for keyword,production in pairs(productions) do
         local printer = printer(keyword, production, printers)
         if printer ~= nil then
            printers[keyword] = printer
         end
      end
      return function(data, file, indent)
         for _,k in ipairs(order) do
            local v = data[normalize_id(k)]
            if v ~= nil then printers[k](v, file, indent) end
         end
      end
   end
   local function key_composer (productions, order)
      local printer = body_printer(productions, order)
      local file = {t={}}
      function file:write (str)
         str = str:match("([^%s]+)")
         if str and #str > 0 and str ~= ";" and str ~= root..'/' then
            table.insert(self.t, str)
         end
      end
      function file:flush ()
         local ret = {}
         for i=1,#self.t,2 do
            local key, value = self.t[i], self.t[i+1]
            table.insert(ret, '['..key.."="..value..']')
         end
         self.t = {}
         return table.concat(ret, '')
      end
      return function (data, path)
         path = path or ''
         printer(data, file, path)
         return file:flush()
      end
   end
   function translators.choice(keyword, production)
      local rtn = {}
      for case, body in pairs(production.choices) do
         for name, statement in pairs(body) do
            rtn[name] = statement
         end
      end
      return rtn
   end
   function handlers.struct(keyword, production)
      local print_body = body_printer(production.members)
      return function(data, file, path)
         print_body(data, file, path..keyword..'/')
      end
   end
   function handlers.array(keyword, production)
      local serialize = value_serializer(production.element_type)
      return function(data, file, indent)
         local count = 1
         for _,v in ipairs(data) do
            print_keyword(keyword.."[position()="..count.."]", file, '')
            file:write(serialize(v))
            file:write('\n')
            count = count + 1
         end
      end
   end
   -- As a special case, the table handler allows the keyword to be nil,
   -- for printing tables at the top level without keywords.
   function handlers.table(keyword, production)
      local key_order, value_order = {}, {}
      for k,_ in pairs(production.keys) do table.insert(key_order, k) end
      for k,_ in pairs(production.values) do table.insert(value_order, k) end
      table.sort(key_order)
      table.sort(value_order)
      local compose_key = key_composer(production.keys, key_order)
      local print_value = body_printer(production.values, value_order)
      if production.key_ctype and production.value_ctype then
         return function(data, file, path)
            for entry in data:iterate() do
               local key = compose_key(entry.key)
               local path = keyword and keyword..key..'/' or key..'/'
               print_value(entry.value, file, path)
            end
         end
      elseif production.string_key then
         local id = normalize_id(production.string_key)
         return function(data, file, path)
            for key, value in pairs(data) do
               local key = compose_key({[id]=key})
               local path = keyword and keyword..key..'/' or key..'/'
               print_value(value, file, path)
            end
         end
      elseif production.key_ctype then
         return function(data, file, path)
            for key, value in cltable.pairs(data) do
               local key = compose_key(key)
               local path = keyword and keyword..key..'/' or key..'/'
               print_value(value, file, path)
            end
         end
      else
         return function(data, file, path)
            for key, value in pairs(data) do
               local key = compose_key(key)
               local path = keyword and keyword..key..'/' or key..'/'
               print_value(value, file, path)
            end
         end
      end
   end
   function handlers.scalar(keyword, production)
      local serialize = value_serializer(production.argument_type)
      return function(data, file, path)
         local str = serialize(data)
         if print_default or str ~= production.default then
            print_keyword(keyword, file, path)
            file:write(str)
            file:write('\n')
         end
      end
   end

   local top_printers = {}
   function top_printers.struct(production)
      local printer = body_printer(production.members)
      return function(data, file)
         printer(data, file, '')
         return file:flush()
      end
   end
   function top_printers.sequence(production)
      local printers = {}
      for k,v in pairs(production.members) do
         printers[k] = printer(k, v)
      end
      return function(data, file)
         for _,elt in ipairs(data) do
            local id = assert(elt.id)
            assert(printers[id])(elt.data, file, '')
         end
         return file:flush()
      end
   end
   function top_printers.table(production)
      local printer = handlers.table(nil, production)
      return function(data, file)
         printer(data, file, '')
         return file:flush()
      end
   end
   function top_printers.array(production)
      local serialize = value_serializer(production.element_type)
      return function(data, file, indent)
         local count = 1
         for _,v in ipairs(data) do
            file:write(root.."[position()="..count.."]")
            file:write(' ')
            file:write(serialize(v))
            file:write('\n')
            count = count + 1
         end
         return file:flush()
      end
   end
   function top_printers.scalar(production)
      local serialize = value_serializer(production.argument_type)
      return function(data, file)
         local str = serialize(data)
         if print_default or str ~= production.default then
            file:write(root)
            file:write(' ')
            file:write(str)
            file:write('\n')
            return file:flush()
         end
      end
   end

   return assert(top_printers[production.type])(production)
end
xpath_printer_from_grammar = util.memoize(xpath_printer_from_grammar)

function data_printer_from_grammar(production, print_default)
   local handlers = {}
   local translators = {}
   local function printer(keyword, production, printers)
      return assert(handlers[production.type])(keyword, production, printers)
   end
   local function print_string(str, file)
      file:write(encode_yang_string(str))
   end
   local function print_keyword(k, file, indent)
      file:write(indent)
      print_string(k, file)
      file:write(' ')
   end
   local function body_printer(productions, order)
      -- Iterate over productions trying to translate to other statements. This
      -- is used for example in choice statements raising the lower statements
      -- in case blocks up to the level of the choice, in place of the choice.
      local translated = {}
      for keyword,production in pairs(productions) do
         local translator = translators[production.type]
         if translator ~= nil then
            local statements = translator(keyword, production)
            for k,v in pairs(statements) do translated[k] = v end
         else
            translated[keyword] = production
         end
      end
      productions = translated
      if not order then
         order = {}
         for k,_ in pairs(productions) do table.insert(order, k) end
         table.sort(order)
      end
      local printers = {}
      for keyword,production in pairs(productions) do
         local printer = printer(keyword, production, printers)
         if printer ~= nil then
            printers[keyword] = printer
         end
      end
      return function(data, file, indent)
         for _,k in ipairs(order) do
            local v = data[normalize_id(k)]
            if v ~= nil then printers[k](v, file, indent) end
         end
      end
   end
   function translators.choice(keyword, production)
      local rtn = {}
      for case, body in pairs(production.choices) do
         for name, statement in pairs(body) do
            rtn[name] = statement
         end
      end
      return rtn
   end
   function handlers.struct(keyword, production)
      local print_body = body_printer(production.members)
      return function(data, file, indent)
         print_keyword(keyword, file, indent)
         file:write('{\n')
         print_body(data, file, indent..'  ')
         file:write(indent..'}\n')
      end
   end
   function handlers.array(keyword, production)
      local serialize = value_serializer(production.element_type)
      return function(data, file, indent)
         for _,v in ipairs(data) do
            print_keyword(keyword, file, indent)
            file:write(serialize(v))
            file:write(';\n')
         end
      end
   end
   -- As a special case, the table handler allows the keyword to be nil,
   -- for printing tables at the top level without keywords.
   function handlers.table(keyword, production)
      local key_order, value_order = {}, {}
      for k,_ in pairs(production.keys) do table.insert(key_order, k) end
      for k,_ in pairs(production.values) do table.insert(value_order, k) end
      table.sort(key_order)
      table.sort(value_order)
      local print_key = body_printer(production.keys, key_order)
      local print_value = body_printer(production.values, value_order)
      if production.key_ctype and production.value_ctype then
         return function(data, file, indent)
            for entry in data:iterate() do
               if keyword then print_keyword(keyword, file, indent) end
               file:write('{\n')
               print_key(entry.key, file, indent..'  ')
               print_value(entry.value, file, indent..'  ')
               file:write(indent..'}\n')
            end
         end
      elseif production.string_key then
         local id = normalize_id(production.string_key)
         return function(data, file, indent)
            for key, value in pairs(data) do
               if keyword then print_keyword(keyword, file, indent) end
               file:write('{\n')
               print_key({[id]=key}, file, indent..'  ')
               print_value(value, file, indent..'  ')
               file:write(indent..'}\n')
            end
         end
      elseif production.key_ctype then
         return function(data, file, indent)
            for key, value in cltable.pairs(data) do
               if keyword then print_keyword(keyword, file, indent) end
               file:write('{\n')
               print_key(key, file, indent..'  ')
               print_value(value, file, indent..'  ')
               file:write(indent..'}\n')
            end
         end
      else
         return function(data, file, indent)
            for key, value in pairs(data) do
               if keyword then print_keyword(keyword, file, indent) end
               file:write('{\n')
               print_key(key, file, indent..'  ')
               print_value(value, file, indent..'  ')
               file:write(indent..'}\n')
            end
         end
      end
   end
   function handlers.scalar(keyword, production)
      local serialize = value_serializer(production.argument_type)
      return function(data, file, indent)
         local str = serialize(data)
         if print_default or str ~= production.default then
            print_keyword(keyword, file, indent)
            file:write(str)
            file:write(';\n')
         end
      end
   end

   local top_printers = {}
   function top_printers.struct(production)
      local printer = body_printer(production.members)
      return function(data, file)
         printer(data, file, '')
         return file:flush()
      end
   end
   function top_printers.sequence(production)
      local printers = {}
      for k,v in pairs(production.members) do
         printers[k] = printer(k, v)
      end
      return function(data, file)
         for _,elt in ipairs(data) do
            local id = assert(elt.id)
            assert(printers[id])(elt.data, file, '')
         end
         return file:flush()
      end
   end
   function top_printers.table(production)
      local printer = handlers.table(nil, production)
      return function(data, file)
         printer(data, file, '')
         return file:flush()
      end
   end
   function top_printers.array(production)
      local serialize = value_serializer(production.element_type)
      return function(data, file, indent)
         for _,v in ipairs(data) do
            file:write(serialize(v))
            file:write('\n')
         end
         return file:flush()
      end
   end
   function top_printers.scalar(production)
      local serialize = value_serializer(production.argument_type)
      return function(data, file)
         file:write(serialize(data))
         return file:flush()
      end
   end
   return assert(top_printers[production.type])(production)
end
data_printer_from_grammar = util.memoize(data_printer_from_grammar)

local function string_output_file()
   local file = {}
   local out = {}
   function file:write(str) table.insert(out, str) end
   function file:flush(str) return table.concat(out) end
   return file
end

function data_printer_from_schema(schema)
   return data_printer_from_grammar(data_grammar_from_schema(schema))
end

function print_data_for_schema(schema, data, file)
   return data_printer_from_schema(schema)(data, file)
end

function print_data_for_schema_by_name(schema_name, data, file)
   local schema = schema.load_schema_by_name(schema_name)
   return print_data_for_schema(schema, data, file)
end

function rpc_input_printer_from_schema(schema)
   return data_printer_from_grammar(rpc_input_grammar_from_schema(schema))
end

function rpc_output_printer_from_schema(schema)
   return data_printer_from_grammar(rpc_output_grammar_from_schema(schema))
end

function selftest()
   print('selfcheck: lib.yang.data')
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
   for i =1,2 do
      assert(data.fruit_bowl.description == 'ohai')
      local contents = data.fruit_bowl.contents
      assert(contents.foo.score == 7)
      assert(contents.foo.tree_grown == nil)
      assert(contents.bar.score == 8)
      assert(contents.bar.tree_grown == nil)
      assert(contents.baz.score == 9)
      assert(contents.baz.tree_grown == true)
      assert(data.addr == util.ipv4_pton('1.2.3.4'))

      local tmp = os.tmpname()
      local file = io.open(tmp, 'w')
      print_data_for_schema(test_schema, data, file)
      file:close()
      local file = io.open(tmp, 'r')
      data = load_data_for_schema(test_schema, file:read('*a'), tmp)
      file:close()
      os.remove(tmp)
   end
   local scalar_uint32 =
      { type='scalar', argument_type={primitive_type='uint32'} }
   local parse_uint32 = data_parser_from_grammar(scalar_uint32)
   local print_uint32 = data_printer_from_grammar(scalar_uint32)
   assert(parse_uint32('1') == 1)
   assert(parse_uint32('"1"') == 1)
   assert(parse_uint32('    "1"   \n  ') == 1)
   assert(print_uint32(1, string_output_file()) == '1')

   -- Verify that lists can lack keys when "config false;" is set.
   local list_wo_key_config_false = [[module config-false-schema {
      namespace "urn:ietf:params:xml:ns:yang:config-false-schema";
      prefix "test";

      container test {
         description "Top level node";
         list node {
            config false;
            description "List without key as config false is set";
            leaf name { type string; }
         }
      }
   }]]
   local keyless_schema = schema.load_schema(list_wo_key_config_false)
   local keyless_list_data = load_data_for_schema(keyless_schema, [[
   test {
      node {
         name "hello";
      }
   }]])

   local test_schema = [[module test-schema {
      namespace "urn:ietf:params:xml:ns:yang:test-schema";
      prefix "test";

      container summary {
         leaf shelves-active {
             type empty;
         }
      }
   }]]
   local loaded_schema = schema.load_schema(test_schema)
   local object = load_data_for_schema(loaded_schema, [[
      summary {
         shelves-active;
      }
   ]])
   assert(object.summary.shelves_active)

   -- Test choice field.
   local choice_schema = schema.load_schema([[module choice-schema {
      namespace "urn:ietf:params:xml:ns:yang:choice-schema";
      prefix "test";

      list boat {
         key "name";
         leaf name { type string; }
         choice country {
            mandatory true;
            case name {
               leaf country-name { type string; }
            }
            case iso-code {
               leaf country-code { type string; }
            }
         }
      }
   }]])
   local choice_data = load_data_for_schema(choice_schema, [[
      boat {
         name "Boaty McBoatFace";
         country-name "United Kingdom";
      }
      boat {
         name "Vasa";
         country-code "SE";
      }
   ]])
   assert(choice_data.boat["Boaty McBoatFace"].country_name == "United Kingdom")
   assert(choice_data.boat["Vasa"].country_code == "SE")

   -- Test mandatory true on choice statement. (should fail)
   local success, err = pcall(load_data_for_schema, choice_schema, [[
      boat {
         name "Boaty McBoatFace";
      }
   ]])
   assert(success == false)

   -- Test default statement.
   local choice_default_schema = schema.load_schema([[module choice-w-default-schema {
      namespace "urn:ietf:params:xml:ns:yang:choice-w-default-schema";
      prefix "test";

      list boat {
         key "name";
         leaf name { type string; }
         choice country {
            default "iso-code";
            case name {
               leaf country-name { type string; }
            }
            case iso-code {
               leaf country-code { type string; default "SE"; }
            }
         }
      }
   }]])

   local choice_data_with_default = load_data_for_schema(choice_default_schema, [[
      boat {
         name "Kronan";
      }
   ]])
   assert(choice_data_with_default.boat["Kronan"].country_code == "SE")

   -- Check that we can't specify both of the choice fields. (should fail)
   local success, err = pcall(load_data_for_schema, choice_schema, [[
      boat {
         name "Boaty McBoatFace";
         country-name "United Kingdom";
         country-code "GB";
      }
   ]])
   assert(success == false)

   print('selfcheck: ok')
end
