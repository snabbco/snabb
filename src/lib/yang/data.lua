-- Use of this source code is governed by the Apache 2.0 license; see
-- COPYING.
module(..., package.seeall)

local mem = require("lib.stream.mem")
local parser_mod = require("lib.yang.parser")
local schema = require("lib.yang.schema")
local util = require("lib.yang.util")
local value = require("lib.yang.value")
local list = require("lib.yang.list")
      typeof = require("lib.yang.ctype").typeof
local ffi = require("ffi")
local lib = require('core.lib')
local regexp = require("lib.xsd_regexp")
local lib = require("core.lib")

function normalize_id(id)
   return (id:gsub('[^%w_]', '_'))
end

-- We need to properly support unions.  It's a big FIXME!  As an
-- intermediate step, we pick the first type in the union.  Terrible.
local function elide_unions(t)
   while t.primitive_type == 'union' do t = t.union[1] end
   return t
end

function data_grammar_from_schema(schema, is_config)
   local function is_empty(tab)
      for k,v in pairs(tab) do return false end
      return true
   end
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
   end
   local function visit_body(node)
      local ret = {}
      local norm = {}
      for k, child in pairs(node.body) do
         local out = visit(child)
         if out then
            ret[k] = out
            local id = normalize_id(k)
            assert(not norm[id], 'duplicate data identifier: '..id)
            norm[id] = k
         end
      end
      return ret
   end
   function handlers.container(node)
      local members = visit_body(node)
      if is_empty(members) then return end
      return {type='struct', members=members, ctype=struct_ctype(members)}
   end
   function handlers.choice(node)
      local choices = {}
      for choice, n in pairs(node.body) do
         if n.kind == 'case' then
            local members = visit_body(n)
            if not is_empty(members) then choices[choice] = members end
         else
            choices[choice] = { [choice] = visit(n) }
         end
      end
      if is_empty(choices) then return end
      return {type="choice", default=node.default, mandatory=node.mandatory,
              choices=choices}
   end
   handlers['leaf-list'] = function(node)
      if node.config ~= is_config then return end
      local t = elide_unions(node.type)
      return {type='array', element_type=t,
              min_elements=node.min_elements, max_elements=node.max_elements}
   end
   function handlers.list(node)
      local norm = {}
      local keys, values = {}, {}
      if node.key then
         for k in node.key:split(' +') do
            local leaf = node.body[k]
            assert(leaf, 'missing key leaf: '..k)
            assert(leaf.kind == 'leaf', 'key not a leaf: '..k)
            assert(not keys[k], 'duplicate key: '..k)
            keys[k] = assert(handlers.leaf(leaf, true))
            local id = normalize_id(k)
            assert(not norm[id], 'duplicate data identifier: '..id)
            norm[id] = k
         end
      end
      for k,node in pairs(node.body) do
         if not keys[k] then
            values[k] = visit(node)
            local id = normalize_id(k)
            assert(not norm[id], 'duplicate data identifier: '..id)
            norm[id] = k
         end
      end
      if is_empty(values) and node.config ~= is_config then return end
      local function list_spec(nodes, builder, validate)
         local spec = {}
         for name, node in pairs(nodes) do
            builder(spec, normalize_id(name), node)
         end
         if validate then validate(spec) end
         return spec
      end
      local function list_key(keys, name, node)
         assert(node.type =='scalar')
         if node.ctype then
            keys[name] = {ctype=node.ctype}
         elseif value_ctype(node.argument_type) then
            keys[name] = {ctype=value_ctype(node.argument_type)}
         else
            keys[name] = {type=node.argument_type.primitive_type}
         end
      end
      local function list_member(members, name, node)
         if node.ctype then
            members[name] = {
               ctype = node.ctype
            }
         elseif node.type == 'scalar' then
            if value_ctype(node.argument_type) then
               members[name] = {
                  ctype = value_ctype(node.argument_type),
                  optional = not (node.default or node.mandatory)
               }
            else
               members[name] = {
                  type = node.argument_type.primitive_type,
                  optional = not (node.default or node.mandatory)
               }
            end
         elseif node.type == 'choice' then
            for _, choices in pairs(node.choices) do
               local choice_members = list_spec(choices, list_member)
               for name, member in pairs(choice_members) do
                  assert(not members[name])
                  members[name] = member
               end
            end
         else
            members[name] = {
               type = 'lvalue',
               optional = not node.mandatory
            }
         end
      end
      local l = {}
      if node.key then
         l.keys = list_spec(keys, list_key, list.validate_keys)
      else
         l.keys = {__ikey={ctype='uint64_t'}}
      end
      l.members = list_spec(values, list_member, list.validate_members)
      l.has_key = node.key and true
      function l.new() return list.new(l.keys, l.members) end
      return {type='list', keys=keys, values=values, list=l,
              unique = node.unique,
              min_elements=node.min_elements, max_elements=node.max_elements}
   end
   function handlers.leaf(node, for_key)
      if node.config ~= is_config and not for_key then return end
      local ctype
      local t = elide_unions(node.type)
      if node.default or node.mandatory then ctype=value_ctype(t) end
      return {type='scalar', argument_type=t,
              default=node.default, mandatory=node.mandatory,
              is_unique = node.is_unique, ctype=ctype}
   end
   local members = visit_body(schema)
   return {type="struct", members=members, ctype=struct_ctype(members)}
end
data_grammar_from_schema = util.memoize(data_grammar_from_schema)

function config_grammar_from_schema(schema)
   return data_grammar_from_schema(schema, true)
end
config_grammar_from_schema = util.memoize(config_grammar_from_schema)

function state_grammar_from_schema(schema)
   return data_grammar_from_schema(schema, false)
end
state_grammar_from_schema = util.memoize(state_grammar_from_schema)

function rpc_grammar_from_schema(schema)
   local grammar = {}
   for _,prop in ipairs({'input', 'output'}) do
      grammar[prop] = { type="sequence", members={} }
      for k,rpc in pairs(schema.rpcs) do
         local node = rpc[prop]
         if node then
            -- Hack to mark RPC is-config as being true
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

local function range_predicate(range, val)
   return function(val)
      for _,part in ipairs(range) do
         local l, r = unpack(part)
         if (l == 'min' or l <= val) and (r == 'max' or val <= r) then
            return true
         end
      end
      return false
   end
end

local function range_validator(range, f)
   if not range then return f end
   local is_in_range = range_predicate(range.value)
   return function(val, P)
      if is_in_range(val) then return f(val, P) end
      P:error('value '..val..' is out of the valid range')
   end
end
local function length_validator(length, f)
   if not length then return f end
   local is_in_range = range_predicate(length.value)
   return function(val, P)
      if is_in_range(string.len(val)) then return f(val, P) end
      P:error('length of string '..val..' is out of the valid range')
   end
end
function pattern_validator(patterns, f)
   if not patterns or #patterns == 0 then return f end
   local compiled = {}
   for _, pattern in ipairs(patterns) do
      compiled[pattern.value] = regexp.compile(pattern.value)
   end
   return function (val, P)
      if type(val) == 'string' then
         for pattern, match in pairs(compiled) do
            if not match(val) then
               P:error("pattern mismatch\n"..pattern.."\n"..val)
            end
         end
      end
      return f(val, P)
   end
end
local function bit_validator(range, f)
   -- FIXME: Implement me!
   return f
end
local function enum_validator(enums, f)
   if not enums then return f end
   return function (val, P)
      if not enums[val] then
         P:error('enumeration '..val..' is not a valid value')
      end
      return f(val, P)
   end
end
local function identityref_validator(bases, default_prefix, f)
   if not default_prefix then return f end
   return function(val, P)
      if not val:match(':') then val = default_prefix..":"..val end
      local identity = schema.lookup_identity(val)
      for _, base in ipairs(bases) do
         if not schema.identity_is_instance_of(identity, base) then
            P:error('identity '..val..' not an instance of '..base)
         end
      end
      return f(val, P)
   end
end

function value_parser(typ)
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
   return function(str, k, P)
      return validate(parse(str, k), P)
   end
end

local function struct_parser(keyword, members, ctype)
   local keys = {}
   for k,v in pairs(members) do table.insert(keys, k) end
   local ret, expanded_members
   local function init()
      ret, expanded_members = {}, {}
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
   end
   local function parse1(P)
      P:skip_whitespace()
      P:consume("{")
      P:skip_whitespace()
      while not P:check("}") do
         local k = P:parse_identifier()
         if k == '' then P:error("Expected a keyword") end
         -- Scalar/array parser responsible for requiring whitespace
         -- after keyword.  Struct/table don't need it as they have
         -- braces.
         local sub = expanded_members[k]
         if not sub then P:error('unrecognized parameter: '..k) end
         local id = normalize_id(k)
         ret[id] = sub.parse(P, ret[id], k)
         P:skip_whitespace()
      end
      return ret
   end
   local function parse(P, out)
      if out ~= nil then P:error('duplicate parameter: '..keyword) end
      return parse1(P)
   end
   local struct_t = ctype and typeof(ctype)
   local function finish(out, leaf)
      for k,_ in pairs(expanded_members) do
         out = out or {}
         local id = normalize_id(k)
         out[id] = expanded_members[k].finish(out[id], k)
      end
     -- FIXME check mandatory values.
      if struct_t then
        return struct_t(out)
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
      return parsev(str, keyword, P)
   end
   local function parse(P, out)
      table.insert(out, parse1(P))
      return out
   end
   local elt_t = ctype and typeof(ctype)
   local array_t = ctype and ffi.typeof('$[?]', elt_t)
   local function finish(out)
      -- FIXME check min-elements
      if out and array_t then
         out = util.ffi_array(array_t(#out, out), elt_t)
      end
      return out
   end
   return {init=init, parse=parse, finish=finish}
end

local default_parser = {}
function default_parser:error (...) error(...) end

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
      return parsev(maybe_str, keyword, P)
   end
   local function parse(P, out)
      if out ~= nil then P:error('duplicate parameter: '..keyword) end
      return parse1(P)
   end
   local function finish(out)
      if out ~= nil then return out end
      if default then return parsev(default, keyword, default_parser) end
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

      -- keep track of initialzed members
      local inits = {}

      local function init() return {} end
      local function parse(P, out, k)
         if chosen and choice_map[k] ~= chosen then
            error("Only one choice set can exist at one time: "..keyword)
         else
            chosen = choice_map[k]
         end
         inits[k] = inits[k] or members[chosen][k].init()
         return members[chosen][k].parse(P, inits[k], k)
      end

      -- This holds a copy of all the nodes so we know when we've hit the last one.
      local function finish(out, k)
         if out ~= nil then return members[chosen][k].finish(out) end
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

function list_parser(keyword, keys, values, spec)
   local members = {}
   for k,v in pairs(keys) do members[k] = v end
   for k,v in pairs(values) do members[k] = v end
   local parser = struct_parser(keyword, members)
   local function init()
      local res = spec.new()
      local l = list.object(res)
      local assoc = {}
      function assoc:add(entry)
         if not spec.has_key then
            entry.__ikey = #res+1
         end
         l:add_entry(entry)
      end
      function assoc:finish() return res end
      return assoc
   end
   local function parse1(P)
      return parser.finish(parser.parse(P, parser.init()))
   end
   local function parse(P, assoc)
      local struct = parse1(P)
      local entry = {}
      for k,_ in pairs(struct) do
         local id = normalize_id(k)
         entry[id] = struct[id]
      end
      assoc:add(entry)
      return assoc
   end
   local function finish(assoc)
      if assoc then
         return assoc:finish()
      end
   end
   return {init=init, parse=parse, finish=finish}
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
   function handlers.list(keyword, production)
      local keys, values = visitn(production.keys), visitn(production.values)
      return list_parser(keyword, keys, values, production.list)
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
      local keys = {}
      for k,v in pairs(members) do table.insert(keys, k) end
      return function(stream)
         local P = parser_mod.Parser.new(stream)
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
         while true do
            P:skip_whitespace()
            if P:is_eof() then break end
            local k = P:parse_identifier()
            if k == '' then P:error("Expected a keyword") end
            local sub = expanded_members[k]
            if not sub then P:error('unrecognized parameter: '..k) end
            local id = normalize_id(k)
            ret[id] = sub.parse(P, ret[id], k)
         end
         for k,sub in pairs(expanded_members) do
            local id = normalize_id(k)
            ret[id] = sub.finish(ret[id], k)
         end
         if struct_t then return struct_t(ret) else return ret end
      end
   end
   function top_parsers.sequence(production)
      local members = visitn(production.members)
      return function(stream)
         local P = parser_mod.Parser.new(stream)
         local ret = {}
         while true do
            P:skip_whitespace()
            if P:is_eof() then break end
            local k = P:parse_identifier()
            P:consume_whitespace()
            local sub = assert(members[k])
            if not sub then P:error('unrecognized rpc: '..k) end
            local data = sub.finish(sub.parse(P, sub.init(), k))
            table.insert(ret, {id=k, data=data})
         end
         return ret
      end
   end
   function top_parsers.array(production)
      local parser = visit1('[bare array]', production)
      return function(stream)
         local P = parser_mod.Parser.new(stream)
         local out = parser.init()
         while true do
            P:skip_whitespace()
            if P:is_eof() then break end
            out = parser.parse(P, out)
         end
         return parser.finish(out)
      end
   end
   function top_parsers.list(production)
      local parser = visit1('[bare list]', production)
      return function(stream)
         local P = parser_mod.Parser.new(stream)
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

      return function(stream)
         local P = parser_mod.Parser.new(stream)
         P:skip_whitespace()
         local str = P:parse_string()
         P:skip_whitespace()
         if not P:is_eof() then P:error("Not end of file") end
         return parse(str, '[bare scalar]', default_parser)
      end
   end
   return assert(top_parsers[production.type])(production)
end
data_parser_from_grammar = util.memoize(data_parser_from_grammar)

function data_parser_from_schema(schema, is_config)
   local grammar = data_grammar_from_schema(schema, is_config)
   return data_parser_from_grammar(grammar)
end

function config_parser_from_schema(schema)
   return data_parser_from_schema(schema, true)
end

function state_parser_from_schema(schema)
   return data_parser_from_schema(schema, false)
end

function load_data_for_schema(schema, stream, is_config)
   return data_parser_from_schema(schema, is_config)(stream)
end

function load_config_for_schema(schema, stream)
   return load_data_for_schema(schema, stream, true)
end

function load_state_for_schema(schema, stream)
   return load_data_for_schema(schema, stream, false)
end

function load_data_for_schema_by_name(schema_name, stream, is_config)
   local schema = schema.load_schema_by_name(schema_name)
   return load_data_for_schema(schema, stream, is_config)
end

function load_config_for_schema_by_name(schema_name, stream)
   return load_data_for_schema_by_name(schema_name, stream, true)
end

function load_state_for_schema_by_name(schema_name, stream)
   return load_data_for_schema_by_name(schema_name, stream, false)
end

function rpc_input_parser_from_schema(schema)
   return data_parser_from_grammar(rpc_input_grammar_from_schema(schema))
end

function rpc_output_parser_from_schema(schema)
   return data_parser_from_grammar(rpc_output_grammar_from_schema(schema))
end

local value_serializers = {}
local function value_serializer(typ)
   local prim = typ.primitive_type
   if value_serializers[prim] then return value_serializers[prim] end
   local tostring = assert(value.types[prim], prim).tostring
   value_serializers[prim] = tostring
   return tostring
end

local function print_yang_string(str, file)
   if #str == 0 then
      file:write("''")
   elseif str:match("^[^%s;{}\"'/]*$") then
      file:write(str)
   else
      file:write('"')
      for i=1,#str do
         local chr = str:sub(i,i)
         if chr == '\n' then
            file:write('\\n')
         elseif chr == '\t' then
            file:write('\\t')
         elseif chr == '"' or chr == '\\' then
            file:write('\\')
            file:write(chr)
         else
            file:write(chr)
         end
      end
      file:write('"')
   end
end

function xpath_printer_from_grammar(production, print_default, root)
   if not root then root = '' end
   if #root == 1 and root:sub(1, 1) == '/' then
      root = ''
   end
   local handlers = {}
   local translators = {}
   local function printer(keyword, production, printers)
      return assert(handlers[production.type])(keyword, production, printers)
   end
   local function print_keyword(k, file, path)
      path = path:sub(1, 1) ~= '[' and root..'/'..path or root..path
      file:write(path)
      print_yang_string(k, file)
      file:write(' ')
   end
   local function body_printer(productions)
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
      local order = {}
      for k,_ in pairs(productions) do table.insert(order, k) end
      table.sort(order)
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
   local function key_composer (productions)
      local printer = body_printer(productions)
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
            print_yang_string(serialize(v), file)
            file:write('\n')
            count = count + 1
         end
      end
   end
   -- As a special case, the list handler allows the keyword to be nil,
   -- for printing lists at the top level without keywords.
   function handlers.list(keyword, production)
      local compose_key = key_composer(production.keys)
      local print_value = body_printer(production.values)
      return function(data, file, path)
         assert(list.object(data))
         path = path or ''
         for _, entry in ipairs(data) do
            local key = compose_key(entry)
            local path = path..(keyword or '')..key..'/'
            print_value(entry, file, path)
         end
      end
   end
   function handlers.scalar(keyword, production)
      local serialize = value_serializer(production.argument_type)
      return function(data, file, path)
         local str = serialize(data)
         if print_default or str ~= production.default then
            print_keyword(keyword, file, path)
            print_yang_string(str, file)
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
   function top_printers.list(production)
      local printer = handlers.list(nil, production)
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
            print_yang_string(serialize(v), file)
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
            print_yang_string(str, file)
            file:write('\n')
            return file:flush()
         end
      end
   end

   return assert(top_printers[production.type])(production)
end
xpath_printer_from_grammar = util.memoize(xpath_printer_from_grammar)

function influxdb_printer_from_grammar(production, print_default, root)
   if not root then root = '' end
   if root and #root == 1 and root:sub(1, 1) == '/' then
      root = ''
   end
   local handlers = {}
   local translators = {}
   local function printer(keyword, production, printers)
      return assert(handlers[production.type])(keyword, production, printers)
   end
   local function escape_double_quotes (value)
      assert(type(value) == 'string')
      return value:gsub('"', '\\"')
   end
   local integers = lib.set('int8','int16','int32','int64',
                            'uint8','uint16','uint32','uint64')
   local function escape_value (primitive_type, val)
      if integers[primitive_type] then
         return tostring(val).."i"
      elseif primitive_type == 'decimal64' then
         return tostring(val)
      elseif primitive_type == 'string' then
         return '"'..escape_double_quotes(val)..'"'
      elseif primitive_type == 'boolean' then
         return val and 'true' or 'false'
      else
         return val
      end
   end
   local function print_entry (file, entry)
      local path, keyword = entry.path, entry.keyword
      local value = entry.value
      if not file.is_tag then value = escape_value(entry.primitive_type, value) end
      if entry.is_unique then
         file:write(keyword)
      else
         path = path..keyword
         if not file.is_tag then path = '/'..path end
         file:write(path)
      end
      if entry.tags then file:write(','..entry.tags) end
      file:write(file.is_tag and value or ' value='..value)
      file:write('\n')
   end
   local function body_printer(productions)
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
      local order = {}
      for k,_ in pairs(productions) do table.insert(order, k) end
      table.sort(order)
      local printers = {}
      for keyword,production in pairs(productions) do
         local printer = printer(keyword, production, printers)
         if printer ~= nil then
            printers[keyword] = printer
         end
      end
      return function(data, file, path, tags)
         for _,k in ipairs(order) do
            local v = data[normalize_id(k)]
            if v ~= nil then printers[k](v, file, path, tags) end
         end
      end
   end
   local function escape_tag (tag)
      return tag:gsub('=', '\\=')
                :gsub(',', '\\,')
                :gsub(' ', '\\ ')
   end
   local function key_composer (productions)
      local printer = body_printer(productions)
      local file = {t={}, is_tag=true}
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
            if key and value then
               table.insert(ret, escape_tag(key).."="..escape_tag(value))
            end
         end
         self.t = {}
         return #ret > 0 and table.concat(ret, ',')
      end
      return function (data, path, tags)
         path = path or ''
         printer(data, file, path, tags)
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
      return function(data, file, path, tags)
         print_body(data, file, path..keyword..'/', tags)
      end
   end
   function handlers.array(keyword, production)
      local serialize = value_serializer(production.element_type)
      return function(data, file, path, tags)
         local count = 1
         for _,v in ipairs(data) do
            local tag, value = '%position='..count, serialize(v)
            local tags = tags and tags..','..tag or tag
            print_entry(file, {keyword=keyword, tags=tags, value=value,
                               path=path, is_unique=production.is_unique,
                               primitive_type=production.primitive_type})
            count = count + 1
         end
      end
   end
   local function is_key_unique (node)
      if not node.keys then return true end
      for k,v in pairs(node.keys) do
         if not v.is_unique then return false end
      end
      return true
   end
   -- As a special case, the list handler allows the keyword to be nil,
   -- for printing lists at the top level without keywords.
   function handlers.list(keyword, production)
      local is_key_unique = is_key_unique(production)
      local compose_key = key_composer(production.keys)
      local print_value = body_printer(production.values)
      return function(data, file, path)
         assert(list.object(data))
         path = path or ''
         for _, entry in ipairs(data) do
            local key = compose_key(entry)
            local path = path..(keyword or '')..'/'
            if not is_key_unique then key = path..key end
            print_value(entry, file, path, key)
         end
      end
   end
   function handlers.scalar(keyword, production)
      local primitive_type = production.argument_type.primitive_type
      local serialize = value_serializer(production.argument_type)
      return function(data, file, path, tags)
         local str = serialize(data)
         if print_default or str ~= production.default then
            print_entry(file, {keyword=keyword, tags=tags, value=str,
                               path=path, is_unique=production.is_unique,
                               primitive_type=primitive_type})
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
   function top_printers.list(production)
      local printer = handlers.list(nil, production)
      return function(data, file)
         printer(data, file, '')
         return file:flush()
      end
   end
   function top_printers.array(production)
      local primitive_type = production.argument_type.primitive_type
      local serialize = value_serializer(production.element_type)
      return function(data, file, path, tags)
         local count = 1
         for _,v in ipairs(data) do
            local tag, value = '%position='..count, serialize(v)
            local tags = tags and tags..','..tag or tag
            print_entry(file, {keyword=keyword, tags=tags, value=value,
                               path=path, is_unique=production.is_unique,
                               primitive_type=production.primitive_type})
            count = count + 1
         end
         return file:flush()
      end
   end
   function top_printers.scalar(production)
      local primitive_type = production.argument_type.primitive_type
      local serialize = value_serializer(production.argument_type)
      return function(data, file, path, tags)
         local str = serialize(data)
         if print_default or str ~= production.default then
            print_entry(file, {keyword=root, tags=tags, value=str,
                               path=path, is_unique=production.is_unique,
                               primitive_type=primitive_type})
            return file:flush()
         end
      end
   end

   return assert(top_printers[production.type])(production)
end
influxdb_printer_from_grammar = util.memoize(influxdb_printer_from_grammar)

function data_printer_from_grammar(production, print_default)
   local handlers = {}
   local translators = {}
   local function printer(keyword, production, printers)
      return assert(handlers[production.type])(keyword, production, printers)
   end
   local function print_keyword(k, file, indent)
      file:write(indent)
      print_yang_string(k, file)
      file:write(' ')
   end
   local function body_printer(productions)
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
      local order = {}
      for k,_ in pairs(productions) do table.insert(order, k) end
      table.sort(order)
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
            print_yang_string(serialize(v), file)
            file:write(';\n')
         end
      end
   end
   -- As a special case, the list handler allows the keyword to be nil,
   -- for printing lists at the top level without keywords.
   function handlers.list(keyword, production)
      local print_key = body_printer(production.keys)
      local print_value = body_printer(production.values)
      return function(data, file, indent)
         assert(list.object(data))
         for _, entry in ipairs(data) do
            if keyword then print_keyword(keyword, file, indent) end
            file:write('{\n')
            print_key(entry, file, indent..'  ')
            print_value(entry, file, indent..'  ')
            file:write(indent..'}\n')
         end
      end
   end
   function handlers.scalar(keyword, production)
      local serialize = value_serializer(production.argument_type)
      return function(data, file, indent)
         local str = serialize(data)
         if print_default or str ~= production.default then
            print_keyword(keyword, file, indent)
            print_yang_string(str, file)
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
   function top_printers.list(production)
      local printer = handlers.list(nil, production)
      return function(data, file)
         printer(data, file, '')
         return file:flush()
      end
   end
   function top_printers.array(production)
      local serialize = value_serializer(production.element_type)
      return function(data, file, indent)
         for _,v in ipairs(data) do
            print_yang_string(serialize(v), file)
            file:write('\n')
         end
         return file:flush()
      end
   end
   function top_printers.scalar(production)
      local serialize = value_serializer(production.argument_type)
      return function(data, file)
         print_yang_string(serialize(data), file)
         return file:flush()
      end
   end
   return assert(top_printers[production.type])(production)
end
data_printer_from_grammar = util.memoize(data_printer_from_grammar)

function data_printer_from_schema(schema, is_config)
   local grammar = data_grammar_from_schema(schema, is_config)
   return data_printer_from_grammar(grammar)
end

function config_printer_from_schema(schema)
   return data_printer_from_schema(schema, true)
end

function state_printer_from_schema(schema)
   return data_printer_from_schema(schema, false)
end

function print_data_for_schema(schema, data, file, is_config)
   return data_printer_from_schema(schema, is_config)(data, file)
end

function print_config_for_schema(schema, data, file)
   return config_printer_from_schema(schema)(data, file)
end

function print_state_for_schema(schema, data, file)
   return state_printer_from_schema(schema)(data, file)
end

function print_data_for_schema_by_name(schema_name, data, file, is_config)
   local schema = schema.load_schema_by_name(schema_name)
   return print_data_for_schema(schema, data, file, is_config)
end

function print_config_for_schema_by_name(schema_name, data, file)
   return print_data_for_schema_by_name(schema_name, data, file, true)
end

function print_state_for_schema_by_name(schema_name, data, file)
   return print_data_for_schema_by_name(schema_name, data, file, false)
end

function rpc_input_printer_from_schema(schema)
   return data_printer_from_grammar(rpc_input_grammar_from_schema(schema))
end

function rpc_output_printer_from_schema(schema)
   return data_printer_from_grammar(rpc_output_grammar_from_schema(schema))
end

local function influxdb_printer_tests ()
   local function lint (text)
      local ret = {}
      for line in text:gmatch("[^\n]+") do
         table.insert(ret, (line:gsub("^%s+", "")))
      end
      return table.concat(ret, "\n")
   end
   local function influxdb_printer_test (test)
      local schema_str, data_str, expected = unpack(test)
      local format = 'influxdb'
      local is_config, print_default = true, true
      local schema = schema.load_schema(schema_str)
      local data = load_config_for_schema(schema, mem.open_input_string(data_str))
      local grammar = data_grammar_from_schema(schema, is_config, format)
      local printer = influxdb_printer_from_grammar(grammar, print_default)
      local actual = mem.call_with_output_string(printer, data)
      assert(actual == lint(expected))
   end
   local test_schema = [[
      module test {
         namespace test;
         prefix test;

         container foo {
            leaf x { type string; }
            leaf y { type string; }
            list bar {
               key baz;
               leaf baz { type string; }
               leaf y { type string; }
               leaf z { type string; }
            }
         }
         container continents {
            grouping country {
               list country {
                  key name;
                  leaf name { type string; mandatory true; }
                  leaf capital { type string; }
                  leaf gdp { type decimal64; }
                  leaf eu-member { type boolean; }
                  leaf main-cities { type string; }
                  leaf population { type uint32; }
               }
            }
            container europe {
               uses country;
            }
            container asia {
               uses country;
            }
         }
         container users {
            leaf-list allow-user {
               type string;
            }
         }
         container nested-list {
            leaf-list foo {
               type string;
            }
            list bar {
               leaf-list foo {
                  type string;
               }
            }
         }
      }
   ]]

   local tests = {
      {test_schema,
      [[
         foo {
            x "x";
            y "y";
            bar {baz "baz"; y "y"; z "z";}
         }
      ]], [[
         /foo/bar/y,baz=baz value="y"
         z,baz=baz value="z"
         x value="x"
         y value="y"
      ]]},
      {test_schema,
      [[
         continents {
            europe {
               country {
                  name "uk";
                  capital "london";
                  eu-member true;
                  main-cities "\"Manchester\", \"Bristol\", \"Liverpool\"";
                  gdp 2.914e9;
                  population 65000000;
               }
            }
            asia {
               country {
                  name "japan";
                  capital "tokyo";
               }
            }
         }
      ]], [[
         capital,name=japan value="tokyo"
         /continents/europe/country/capital,continents/europe/country/name=uk value="london"
         /continents/europe/country/eu-member,continents/europe/country/name=uk value=true
         /continents/europe/country/gdp,continents/europe/country/name=uk value=2914000000
         /continents/europe/country/main-cities,continents/europe/country/name=uk value="\"Manchester\", \"Bristol\", \"Liverpool\""
         /continents/europe/country/population,continents/europe/country/name=uk value=65000000i
      ]]},
      {test_schema,
      [[
         users {
            allow-user "jane";
         }
      ]], [[
         /users/allow-user,%position=1 value=jane
      ]]},
      {test_schema,
      [[
         nested-list {
            foo "jane";
            bar {
               foo "john";
            }
         }
      ]], [[
         /nested-list/bar/foo,%position=1 value=john
         /nested-list/foo,%position=1 value=jane
      ]]},
   }
   for _, each in ipairs(tests) do
      influxdb_printer_test(each)
   end
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
         leaf material {
            type enumeration {
               enum wood;
               enum glass;
               enum plastic;
            }
         }
         list contents { uses fruit; key name; ordered-by user; }
      }
      leaf addr {
         description "internet of fruit";
         type inet:ipv4-address;
      }

      leaf-list address {
         type inet:ip-prefix;
         description
         "Address prefixes bound to this interface.";
      }

      list choices {
         key id;
         leaf id { type string; }
         choice choice {
            leaf red { type string; }
            leaf blue { type string; }
         }
      }
   }]])

   local data = load_config_for_schema(test_schema,
                                       mem.open_input_string [[
     fruit-bowl {
       description 'ohai';
       material glass;
       contents { name foo; score 7; }
       contents { name bar; score 8; }
       contents { name baz; score 9; tree-grown true; }
     }
     addr 1.2.3.4;
     address 1.2.3.4/24;
     choices { id "one"; blue "hey"; }
     choices { id "two"; red "bye"; }

   ]])
   for i =1,2 do
      assert(data.fruit_bowl.description == 'ohai')
      assert(data.fruit_bowl.material == 'glass', data.material)
      local contents = data.fruit_bowl.contents
      assert(contents.foo.score == 7)
      assert(contents.foo.tree_grown == nil)
      assert(contents.bar.score == 8)
      assert(contents.bar.tree_grown == nil)
      assert(contents.baz.score == 9)
      assert(contents.baz.tree_grown == true)
      assert(data.addr == util.ipv4_pton('1.2.3.4'))
      assert(data.choices.one.blue == "hey")
      assert(data.choices.two.red == "bye")

      -- Check list order
      local score, total = 0, 0
      for i, content in ipairs(contents) do
         assert(score < content.score, "ipairs out of order: "..i)
         score = content.score
         total = total + 1
      end
      assert(total == #contents)
      local score, total = 0, 0
      for i, content in pairs(contents) do
         assert(score < content.score, "pairs out of order: "..i)
         score = content.score
         total = total + 1
      end
      assert(total == #contents)

      local stream = mem.tmpfile()
      print_config_for_schema(test_schema, data, stream)
      stream:seek('set', 0)
      data = load_config_for_schema(test_schema, stream)
   end
   local scalar_uint32 =
      { type='scalar', argument_type={primitive_type='uint32'} }
   local parse_uint32 = data_parser_from_grammar(scalar_uint32)
   local print_uint32 = data_printer_from_grammar(scalar_uint32)
   assert(parse_uint32(mem.open_input_string('1')) == 1)
   assert(parse_uint32(mem.open_input_string('"1"')) == 1)
   assert(parse_uint32(mem.open_input_string('    "1"   \n  ')) == 1)
   assert(mem.call_with_output_string(print_uint32, 1) == '1')

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
   local keyless_list_data = load_state_for_schema(keyless_schema,
                                                   mem.open_input_string [[
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
   local object = load_config_for_schema(loaded_schema,
                                         mem.open_input_string [[
      summary {
         shelves-active;
      }
   ]])
   assert(object.summary.shelves_active)

   -- Test nested defaults
   local default_schema = [[module default-schema {
      namespace "urn:ietf:params:xml:ns:yang:default-schema";
      prefix "default";

      container optional {
         leaf default {
             type string;
             default "foo";
         }
      }
   }]]
   local loaded_schema = schema.load_schema(default_schema)
   local object = load_config_for_schema(loaded_schema,
                                         mem.open_input_string "")
   assert(object.optional)
   assert(object.optional.default == "foo")

   local default2_schema = [[module default2-schema {
      namespace "urn:ietf:params:xml:ns:yang:default2-schema";
      prefix "default";

      container optional1 {
         container optional2 {
            leaf default {
               type string;
               default "foo";
            }
         }
      }
   }]]
   local loaded_schema = schema.load_schema(default2_schema)
   local object = load_config_for_schema(loaded_schema,
                                         mem.open_input_string "")
   assert(object.optional1)
   assert(object.optional1.optional2)
   assert(object.optional1.optional2.default == "foo")

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
   local choice_data = load_config_for_schema(choice_schema,
                                              mem.open_input_string [[
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
   local success, err = pcall(load_config_for_schema, choice_schema,
                              mem.open_input_string [[
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

   local choice_data_with_default = load_config_for_schema(choice_default_schema,
                                                           mem.open_input_string [[
      boat {
         name "Kronan";
      }
   ]])
   assert(choice_data_with_default.boat["Kronan"].country_code == "SE")

   -- Check that we can't specify both of the choice fields. (should fail)
   local success, err = pcall(load_config_for_schema, choice_schema,
                              mem.open_input_string [[
      boat {
         name "Boaty McBoatFace";
         country-name "United Kingdom";
         country-code "GB";
      }
   ]])
   assert(success == false)

   -- Check native number key.
   local native_number_key_schema = schema.load_schema([[module native-number-key {
      namespace "urn:ietf:params:xml:ns:yang:native-number-key";
      prefix "test";

      list number {
         key "number";
         leaf number { type uint32; }
         leaf name { type string; }
      }
   }]])

   local native_number_key_data = load_config_for_schema(
      native_number_key_schema,
      mem.open_input_string [[
         number {
            number 1;
            name "Number one!";
         }
   ]])
   assert(native_number_key_data.number[1].name == "Number one!")

   -- Test top-level choice with list member.
   local choice_schema = schema.load_schema([[module toplevel-choice-schema {
      namespace "urn:ietf:params:xml:ns:yang:toplevel-choice-schema";
      prefix "test";

      choice test {
        case this {
          leaf foo { type string; }
          leaf bar { type string; }
        }
        case that {
          leaf baz { type uint32; }
          list qu-x { key id; leaf id { type string; } leaf v { type string; } }
        }
      }
   }]])
   local choice_data = load_config_for_schema(choice_schema,
                                              mem.open_input_string [[
      foo "hello";
      bar "world";
   ]])
   assert(choice_data.foo == "hello")
   assert(choice_data.bar == "world")
   local choice_data = load_config_for_schema(choice_schema,
                                              mem.open_input_string [[
      baz 1;
      qu-x { id "me"; v "hey"; }
      qu-x { id "you"; v "hi"; }
   ]])
   assert(choice_data.baz == 1)
   assert(choice_data.qu_x.me.v == "hey")
   assert(choice_data.qu_x.you.v == "hi")

   -- Test choice with case short form.
   local choice_schema = schema.load_schema([[module shortform-choice-schema {
      namespace "urn:ietf:params:xml:ns:yang:shortform-choice-schema";
      prefix "test";

      choice test {
        default foo;
        leaf foo { type string; default "something"; }
        leaf bar { type string; }
      }
   }]])
   local choice_data = load_config_for_schema(choice_schema,
                                              mem.open_input_string "")
   assert(choice_data.foo == "something")

   -- Test range / length restrictions.
   local range_length_schema = schema.load_schema([[module range-length-schema {
      namespace "urn:ietf:params:xml:ns:yang:range-length-schema";
      prefix "test";

      leaf-list range_test {
         type uint8 { range 1..10|20..30; }
      }
      leaf-list length_test {
         type string { length 1..10|20..30; }
      }
   }]])

   -- Test range validation. (should fail)
   local success, err = pcall(load_config_for_schema, range_length_schema,
                              mem.open_input_string [[
      range_test 9;
      range_test 35;
   ]])
   assert(success == false)

   -- Test length validation. (should fail)
   local success, err = pcall(load_config_for_schema, range_length_schema,
                              mem.open_input_string [[
      length_test "+++++++++++++++++++++++++++++++++++";
      length_test "...............";
   ]])
   assert(success == false)

   -- Test range validation. (should succeed)
   local success, err = pcall(load_config_for_schema, range_length_schema,
                              mem.open_input_string [[
      range_test 9;
      range_test 22;
   ]])
   assert(success)

   -- Test length validation. (should succeed)
   local success, err = pcall(load_config_for_schema, range_length_schema,
                              mem.open_input_string [[
      length_test ".........";
      length_test "++++++++++++++++++++++";
   ]])
   assert(success)

   -- Test native numeric keys.
   local natnumkey_schema = schema.load_schema([[module native-numeric-schema {
      namespace "urn:ietf:params:xml:ns:yang:native-numeric-schema";
      prefix "test";

      list numbered {
         key "id";
         leaf id { type int32; }
         leaf bo { type boolean; default true; }
      }
   }]])
   local natnumkey_data = load_config_for_schema(natnumkey_schema,
      mem.open_input_string [[
      numbered { id -1; }
      numbered { id 2; }
   ]])
   assert(natnumkey_data.numbered[-1])
   assert(natnumkey_data.numbered[2])

   influxdb_printer_tests()

   print('selfcheck: ok')
end
