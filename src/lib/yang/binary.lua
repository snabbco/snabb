-- Use of this source code is governed by the Apache 2.0 license; see
-- COPYING.
module(..., package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local lib = require("core.lib")
local shm = require("core.shm")
local file = require("lib.stream.file")
local schema = require("lib.yang.schema")
local util = require("lib.yang.util")
local value = require("lib.yang.value")
local data = require('lib.yang.data')
local cdata = require('lib.yang.ctype')
local list = require("lib.yang.list")

local MAGIC = "yangconf"
local VERSION = 0x0000f300

local header_t = ffi.typeof([[
struct {
   uint8_t magic[8];
   uint32_t version;
   uint64_t source_mtime_sec;
   uint32_t source_mtime_nsec;
   uint32_t schema_name;
   uint32_t revision_date;
   uint64_t data_start;
   uint64_t data_len;
   uint64_t strtab_start;
   uint64_t strtab_len;
}
]])
local uint32_t = ffi.typeof('uint32_t')

-- A string table is written out as a uint32 count, followed by that
-- many offsets indicating where the Nth string ends, followed by the
-- string data for those strings.
local function string_table_builder()
   local strtab = {}
   local strings = {}
   local count = 0
   function strtab:intern(str)
      if strings[str] then return strings[str] end
      strings[str] = count
      count = count + 1
      return strings[str]
   end
   function strtab:emit(stream)
      local by_index = {}
      for str, idx in pairs(strings) do by_index[idx] = str end
      local strtab_start = assert(stream:seek())
      stream:write_scalar(uint32_t, count)
      local str_end = 0
      for i=0,count-1 do
         str_end = str_end + by_index[i]:len()
         stream:write_scalar(uint32_t, str_end)
      end
      for i=0,count-1 do
         str_end = str_end + by_index[i]:len()
         stream:write_bytes(by_index[i], by_index[i]:len())
      end
      return strtab_start, assert(stream:seek()) - strtab_start
   end
   return strtab
end

local function read_string_table(stream, strtab_len)
   assert(strtab_len >= 4)
   local count = stream:read_scalar(nil, uint32_t)
   assert(strtab_len >= (4 * (count + 1)))
   local offsets = stream:read_array(nil, uint32_t, count)
   assert(strtab_len == (4 * (count + 1)) + offsets[count-1])
   local strings = {}
   local offset = 0
   for i=0,count-1 do
      local len = offsets[i] - offset
      assert(len >= 0)
      strings[i] = stream:read_chars(len)
      offset = offset + len
   end
   return strings
end

local value_emitters = {}
local function value_emitter(ctype)
   if value_emitters[ctype] then return value_emitters[ctype] end
   local type = cdata.typeof(ctype)
   local align = ffi.alignof(type)
   local size = ffi.sizeof(type)
   local buf = ffi.typeof('$[1]', type)()
   local function emit(val, stream)
      buf[0] = val
      stream:write_array(type, buf, 1)
   end
   value_emitters[ctype] = emit
   return emit
end

local function table_size(tab)
   local size = 0
   for k,v in pairs(tab) do size = size + 1 end
   return size
end

local SPARSE_ARRAY_END = 0xffffffff

local function data_emitter(production)
   local handlers = {}
   local translators = {}
   local function visit1(production)
      return assert(handlers[production.type])(production)
   end
   local function expand(production)
      if production.type ~= "struct" then return production end
      local expanded = {}
      for keyword,prod in pairs(production.members) do
         if translators[prod.type] ~= nil then
            translators[prod.type](expanded, keyword, prod)
         else
            expanded[keyword] = prod
         end
      end
      return {type="struct", members=expanded}
   end
   local function visitn(productions)
      local ret = {}
      local expanded_production = productions
      for keyword, production in pairs(productions) do
         expanded_production[keyword] = expand(production)
      end
      for keyword,production in pairs(expanded_production) do
         ret[keyword] = visit1(production)
      end
      return ret
   end
   function translators.choice(productions, keyword, production)
      -- Now bring the choice statements up to the same level replacing it.
      for case, block in pairs(production.choices) do
         for name, body in pairs(block) do productions[name] = body end
      end
   end
   function handlers.struct(production)
      local member_keys = {}
      for k,_ in pairs(production.members) do table.insert(member_keys, k) end
      local function order_predicate (x, y)
         if (type(x) == 'number' and type(y) == 'number') or
            (type(x) == 'string' and type(y) == 'string') then
            return x >= y
         else
            return type(y) == 'number'
         end
      end
      table.sort(member_keys, order_predicate)
      if production.ctype then
         local data_t = cdata.typeof(production.ctype)
         return function(data, stream)
            stream:write_stringref('cstruct')
            stream:write_stringref(production.ctype)
            stream:write_struct(data_t, data)
         end
      else
         local emit_member = visitn(production.members)
         local normalize_id = data.normalize_id
         return function(data, stream)
            stream:write_stringref('lstruct')
            -- We support Lua tables with string and number (<=uint32_t) keys,
            -- first we emit the number keyed members...
            local outn = {}
            for _,k in ipairs(member_keys) do
               if type(k) == 'number' then
                  local id = tonumber(ffi.cast("uint32_t", k))
                  assert(id == k)
                  if data[id] ~= nil then
                     table.insert(outn, {id, emit_member[k], data[id]})
                  end
               end
            end
            stream:write_scalar(uint32_t, #outn)
            for _,elt in ipairs(outn) do
               local id, emit, data = unpack(elt)
               stream:write_scalar(uint32_t, id)
               emit(data, stream)
            end
            -- ...and then the string keyed members.
            local outs = {}
            for _,k in ipairs(member_keys) do
               if type(k) == 'string' then
                  local id = normalize_id(k)
                  if data[id] ~= nil then
                     table.insert(outs, {id, emit_member[k], data[id]})
                  end
               end
            end
            stream:write_scalar(uint32_t, #outs)
            for _,elt in ipairs(outs) do
               local id, emit, data = unpack(elt)
               stream:write_stringref(id)
               emit(data, stream)
            end
         end
      end
   end
   function handlers.array(production)
      if production.ctype then
         local data_t = cdata.typeof(production.ctype)
         return function(data, stream)
            stream:write_stringref('carray')
            stream:write_stringref(production.ctype)
            stream:write_scalar(uint32_t, #data)
            stream:write_array(data_t, data.ptr, #data)
         end
      else
         local emit_tagged_value = visit1(
            {type='scalar', argument_type=production.element_type})
         return function(data, stream)
            stream:write_stringref('larray')
            stream:write_scalar(uint32_t, #data)
            for i=1,#data do emit_tagged_value(data[i], stream) end
         end
      end
   end
   function handlers.list(production)
      local fieldspec_production = {
         type = 'struct',
         members = {
            type = {
               type = 'scalar',
               argument_type = { primitive_type = 'string' }
            },
            ctype = {
               type = 'scalar',
               argument_type = { primitive_type = 'string' }
            },
            optional = {
               type = 'scalar',
               argument_type = { primitive_type = 'boolean' },
               ctype = value.types.boolean.ctype
            }
         }
      }
      local function spec_production (spec)
         local p = {type='struct', members={}}
         for name in pairs(spec) do
            p.members[name] = fieldspec_production
         end
         return p
      end
      local emit_list_keys =
         handlers.struct(spec_production(production.list.keys))
      local emit_list_members =
         handlers.struct(spec_production(production.list.members))
      local emit_member = visitn(production.values)
      for k, emit in pairs(emit_member) do
         emit_member[data.normalize_id(k)] = emit
      end
      return function(data, stream)
         stream:write_stringref('list')
         local l = assert(list.object(data))
         emit_list_keys(l.keys, stream)
         emit_list_members(l.members, stream)
         for k, values in pairs(l.lvalues) do
            stream:write_stringref(k)
            for i,v in pairs(values) do
               assert(i < SPARSE_ARRAY_END)
               stream:write_scalar(uint32_t, i)
               emit_member[k](v, stream)
            end
            stream:write_scalar(uint32_t, SPARSE_ARRAY_END)
         end
         l:save(stream)
      end
   end
   local native_types = lib.set('enumeration', 'identityref', 'leafref', 'string')
   function handlers.scalar(production)
      local primitive_type = production.argument_type.primitive_type
      local type = assert(value.types[primitive_type], "unsupported type: "..primitive_type)
      -- FIXME: needs a case for unions
      if native_types[primitive_type] then
         return function(data, stream)
            stream:write_stringref('stringref')
            stream:write_stringref(data)
         end
      elseif primitive_type == 'empty' then
         return function (data, stream)
            stream:write_stringref('flag')
            stream:write_scalar(uint32_t, data and 1 or 0)
         end
      elseif type.ctype then
         local ctype = type.ctype
         local emit_value = value_emitter(ctype)
         local serialization = 'cscalar'
         if ctype:match('[{%[]') then serialization = 'cstruct' end
         return function(data, stream)
            stream:write_stringref(serialization)
            stream:write_stringref(ctype)
            emit_value(data, stream)
         end
      else
         error("unimplemented: "..primitive_type)
      end
   end

   return visit1(production)
end

function data_compiler_from_grammar(emit_data, schema_name, schema_revision)
   return function(data, filename, source_mtime)
      source_mtime = source_mtime or {sec=0, nsec=0}
      local stream = file.tmpfile("rusr,wusr,rgrp,roth", lib.dirname(filename))
      local strtab = string_table_builder()
      local header = header_t(
         MAGIC, VERSION, source_mtime.sec, source_mtime.nsec,
         strtab:intern(schema_name), strtab:intern(schema_revision or ''))
      -- Write with empty data_len etc, fix it later.
      stream:write_struct(header_t, header)
      header.data_start = assert(stream:seek())
      function stream:write_stringref(str)
         return self:write_scalar(uint32_t, strtab:intern(str))
      end
      emit_data(data, stream)
      header.data_len = assert(stream:seek()) - header.data_start
      header.strtab_start, header.strtab_len = strtab:emit(stream)
      assert(stream:seek('set', 0))
      -- Fix up header.
      stream:write_struct(header_t, header)
      stream:rename(filename)
      stream:close()
   end
end

function data_compiler_from_schema(schema, is_config)
   local grammar = data.data_grammar_from_schema(schema, is_config)
   return data_compiler_from_grammar(data_emitter(grammar),
                                     schema.id, schema.last_revision)
end

function config_compiler_from_schema(schema)
   return data_compiler_from_schema(schema, true)
end

function state_compiler_from_schema(schema)
   return data_compiler_from_schema(schema, false)
end

function compile_config_for_schema(schema, data, filename, source_mtime)
   return config_compiler_from_schema(schema)(data, filename, source_mtime)
end

function compile_config_for_schema_by_name(schema_name, data, filename, source_mtime)
   return compile_config_for_schema(schema.load_schema_by_name(schema_name),
                                    data, filename, source_mtime)
end

-- Hackily re-use the YANG serializer for Lua data consisting of tables,
-- ffi data, numbers, and strings.  Truly a hack; to be removed in the
-- all-singing YANG future that we deserve where all data has an
-- associated schema.
local function ad_hoc_grammar_from_data(data)
   if type(data) == 'table' then
      local members = {}
      for k,v in pairs(data) do
         assert(type(k) == 'string' or type(k) == 'number')
         members[k] = ad_hoc_grammar_from_data(v)
      end
      return {type='struct', members=members}
   elseif type(data) == 'cdata' then
      -- Hackety hack.
      local ctype = tostring(ffi.typeof(data)):match('^ctype<(.*)>$')
      local primitive_types = {
         ['unsigned char [4]']     = 'legacy-ipv4-address',
         ['unsigned char (&)[4]']  = 'legacy-ipv4-address',
         ['unsigned char [6]']     = 'mac-address',
         ['unsigned char (&)[6]']  = 'mac-address',
         ['unsigned char [16]']    = 'ipv6-address',
         ['unsigned char (&)[16]'] = 'ipv6-address',
         ['uint8_t']  = 'uint8',  ['int8_t']  = 'int8',
         ['uint16_t'] = 'uint16', ['int16_t'] = 'int16',
         ['uint32_t'] = 'uint32', ['int32_t'] = 'int32',
         ['uint64_t'] = 'uint64', ['int64_t'] = 'int64',
         ['double'] = 'decimal64' -- ['float'] = 'decimal64',
      }
      local prim = primitive_types[ctype]
      if not prim then error('unhandled ffi ctype: '..ctype) end
      return {type='scalar', argument_type={primitive_type=prim}}
   elseif type(data) == 'number' then
      return {type='scalar', argument_type={primitive_type='decimal64'}}
   elseif type(data) == 'string' then
      return {type='scalar', argument_type={primitive_type='string'}}
   elseif type(data) == 'boolean' then
      return {type='scalar', argument_type={primitive_type='boolean'}}
   else
      error('unhandled data type: '..type(data))
   end
end

function compile_ad_hoc_lua_data_to_file(file_name, data)
   local grammar = ad_hoc_grammar_from_data(data)
   local emitter = data_emitter(grammar)
   -- Empty string as schema name; a hack.
   local compiler = data_compiler_from_grammar(emitter, '')
   return compiler(data, file_name)
end

local function read_compiled_data(stream, strtab)
   local function read_string()
      return assert(strtab[stream:read_scalar(nil, uint32_t)])
   end

   local readers = {}
   local function read1()
      local tag = read_string()
      return assert(readers[tag], tag)()
   end
   function readers.lstruct()
      local ret = {}
      for i=1,stream:read_scalar(nil, uint32_t) do
         local k = stream:read_scalar(nil, uint32_t)
         ret[k] = read1()
      end
      for i=1,stream:read_scalar(nil, uint32_t) do
         local k = read_string()
         ret[k] = read1()
      end
      return ret
   end
   function readers.carray()
      local ctype = cdata.typeof(read_string())
      local count = stream:read_scalar(nil, uint32_t)
      return util.ffi_array(stream:read_array(nil, ctype, count), ctype, count)
   end
   function readers.larray()
      local ret = {}
      for i=1,stream:read_scalar(nil, uint32_t) do table.insert(ret, read1()) end
      return ret
   end
   function readers.list()
      local keys = read1()
      local members = read1()
      local lvalues = {}
      for _, spec in pairs(members) do
         if spec.type == 'lvalue' then
            local name = read_string()
            lvalues[name] = {}
            while true do
               local i = stream:read_scalar(nil, uint32_t)
               if i == SPARSE_ARRAY_END then break end
               lvalues[name][i] = read1()
            end
         end
      end
      return list.load(stream, keys, members, lvalues)
   end
   function readers.stringref()
      return read_string()
   end
   function readers.cstruct()
      local ctype = cdata.typeof(read_string())
      return stream:read_struct(nil, ctype)
   end
   function readers.cscalar()
      local ctype = cdata.typeof(read_string())
      return stream:read_scalar(nil, ctype)
   end
   function readers.flag()
      if stream:read_scalar(nil, uint32_t) ~= 0 then return true end
      return nil
   end
   return read1()
end

function has_magic(stream)
   local success, header = pcall(stream.read_struct, stream, nil, header_t)
   if success then assert(stream:seek('cur', 0) == ffi.sizeof(header_t)) end
   assert(stream:seek('set', 0))
   return success and ffi.string(header.magic, ffi.sizeof(header.magic)) == MAGIC
end

function load_compiled_data(stream)
   local header = stream:read_struct(nil, header_t)
   assert(ffi.string(header.magic, ffi.sizeof(header.magic)) == MAGIC,
          "expected file to begin with "..MAGIC)
   assert(header.version == VERSION,
          "incompatible version: "..header.version)
   assert(stream:seek('set', header.strtab_start))
   local strtab = read_string_table(stream, header.strtab_len)
   local ret = {}
   ret.schema_name = strtab[header.schema_name]
   ret.revision_date = strtab[header.revision_date]
   ret.source_mtime = {sec=header.source_mtime_sec,
                       nsec=header.source_mtime_nsec}
   assert(stream:seek('set', header.data_start))
   ret.data = read_compiled_data(stream, strtab)
   assert(assert(stream:seek()) == header.data_start + header.data_len)
   return ret
end

function load_compiled_data_file(filename)
   return load_compiled_data(assert(file.open(filename)))
end

function data_copier_from_grammar(production)
   local compile = data_compiler_from_grammar(data_emitter(production), '')
   return function(data)
      return function()
         local basename = 'copy-'..lib.random_printable_string(160)
         local tmp = shm.root..'/'..shm.resolve(basename)
         compile(data, tmp)
         local copy = load_compiled_data_file(tmp).data
         S.unlink(tmp)
         return copy
      end
   end
end

function data_copier_for_schema(schema, is_config)
   local grammar = data.data_grammar_from_schema(schema, is_config)
   return data_copier_from_grammar(grammar)
end

function config_copier_for_schema(schema)
   return data_copier_for_schema(schema, true)
end

function state_copier_for_schema(schema)
   return data_copier_for_schema(schema, false)
end

function config_copier_for_schema_by_name(schema_name)
   return config_copier_for_schema(schema.load_schema_by_name(schema_name))
end

function copy_config_for_schema(schema, data)
   return config_copier_for_schema(schema)(data)()
end

function copy_config_for_schema_by_name(schema_name, data)
   return config_copier_for_schema_by_name(schema_name)(data)()
end

function selftest()
   print('selfcheck: lib.yang.binary')
   do
      -- Test Lua table support
      local data = { foo = 12, [42] = { [43] = "bar", baz = 44 } }
      local tmp = os.tmpname()
      compile_ad_hoc_lua_data_to_file(tmp, data)
      local data2 = load_compiled_data_file(tmp).data
      assert(lib.equal(data, data2))
   end
   local test_schema = schema.load_schema([[module snabb-simple-router {
      namespace snabb:simple-router;
      prefix simple-router;

      import ietf-inet-types {prefix inet;}
      import ietf-yang-types { prefix yang; }

      leaf is-active { type boolean; default true; }

      leaf-list integers { type uint32; }
      leaf-list addrs { type inet:ipv4-address; }

      typedef severity  {
         type enumeration {
            enum indeterminate;
            enum minor {
               value 3;
            }
            enum warning {
               value 4;
            }
         }
      }

      container routes {
         list route {
            key addr;
            leaf addr { type inet:ipv4-address; mandatory true; }
            leaf port { type uint8 { range 0..11; } mandatory true; }
            container metadata {
               leaf info { type string; }
            }
         }
         leaf severity {
            type severity;
         }
      }

      container next-hop {
         choice address {
            case mac {
               leaf mac { type yang:mac-address; }
            }
            case ipv4 {
               leaf ipv4 { type inet:ipv4-address; }
            }
            case ipv6 {
               leaf ipv6 { type inet:ipv6-address; }
            }
         }
      }

      container foo {
         leaf enable-qos {
            type empty;
         }
      }
   }]])
   local mem = require('lib.stream.mem')
   local data = data.load_config_for_schema(test_schema,
                                            mem.open_input_string [[
      is-active true;
      integers 1;
      integers 2;
      integers 0xffffffff;
      addrs 4.3.2.1;
      addrs 5.4.3.2;
      routes {
        route { addr 1.2.3.4; port 1; }
        route { addr 2.3.4.5; port 10; metadata { info "bar"; } }
        route { addr 3.4.5.6; port 2; metadata { info "foo"; } }
        severity minor;
      }
      next-hop {
         ipv4 5.6.7.8;
      }
      foo {
         enable-qos;
      }
   ]])

   local ipv4 = require('lib.protocol.ipv4')

   for i=1,3 do
      assert(data.is_active == true)
      assert(#data.integers == 3)
      assert(data.integers[1] == 1)
      assert(data.integers[2] == 2)
      assert(data.integers[3] == 0xffffffff)
      assert(#data.addrs == 2)
      assert(data.addrs[1]==util.ipv4_pton('4.3.2.1'))
      assert(data.addrs[2]==util.ipv4_pton('5.4.3.2'))
      local routing_table = data.routes.route
      assert(routing_table[util.ipv4_pton('1.2.3.4')].port == 1)
      assert(routing_table[util.ipv4_pton('2.3.4.5')].port == 10)
      assert(routing_table[util.ipv4_pton('3.4.5.6')].port == 2)
      assert(
         data.next_hop.ipv4 == util.ipv4_pton('5.6.7.8'),
         "Choice type test failed (round: "..i..")"
      )

      local tmp = os.tmpname()
      compile_config_for_schema(test_schema, data, tmp)
      local data2 = load_compiled_data_file(tmp)
      assert(data2.schema_name == 'snabb-simple-router')
      assert(data2.revision_date == '')
      data = copy_config_for_schema(test_schema, data2.data)
      os.remove(tmp)
   end
   print('selfcheck: ok')
end
