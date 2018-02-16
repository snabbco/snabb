-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local S = require("syscall")
local channel = require("lib.ptree.channel")
local ffi = require("ffi")

local UINT32_MAX = 0xffffffff

local alarm_names = { 'raise_alarm', 'clear_alarm', 'add_to_inventory', 'declare_alarm' }
local alarm_codes = {}
for i, name in ipairs(alarm_names) do alarm_codes[name] = i end

local alarms = {}

function alarms.raise_alarm (codec, resource, alarm_type_id, alarm_type_qualifier,
   perceived_severity, alarm_text)

   local resource = codec:string(resource)
   local alarm_type_id = codec:string(alarm_type_id)
   local alarm_type_qualifier = codec:string(alarm_type_qualifier)

   local perceived_severity = codec:maybe_string(perceived_severity)
   local alarm_text = codec:maybe_string(alarm_text)

   return codec:finish(resource, alarm_type_id, alarm_type_qualifier,
                       perceived_severity, alarm_text)
end
function alarms.clear_alarm (codec, resource, alarm_type_id, alarm_type_qualifier)
   local resource = codec:string(resource)
   local alarm_type_id = codec:string(alarm_type_id)
   local alarm_type_qualifier = codec:string(alarm_type_qualifier)

   return codec:finish(resource, alarm_type_id, alarm_type_qualifier)
end
function alarms.add_to_inventory (codec, alarm_type_id, alarm_type_qualifier,
   resource, has_clear, description)

   local alarm_type_id = codec:string(alarm_type_id)
   local alarm_type_qualifier = codec:maybe_string(alarm_type_qualifier)

   local resource = codec:string(resource)
   local has_clear = codec:string((has_clear and "true" or "false"))
   local description = codec:maybe_string(description)

   return codec:finish(alarm_type_id, alarm_type_qualifier,
                       resource, has_clear, description)
end
function alarms.declare_alarm (codec, resource, alarm_type_id, alarm_type_qualifier,
   perceived_severity, alarm_text)

   local resource = codec:string(resource)
   local alarm_type_id = codec:string(alarm_type_id)
   local alarm_type_qualifier = codec:maybe_string(alarm_type_qualifier)

   local perceived_severity = codec:maybe_string(perceived_severity)
   local alarm_text = codec:maybe_string(alarm_text)

   return codec:finish(resource, alarm_type_id, alarm_type_qualifier,
                       perceived_severity, alarm_text)
end

local function encoder()
   local encoder = { out = {} }
   function encoder:uint32(len)
      table.insert(self.out, ffi.new('uint32_t[1]', len))
   end
   function encoder:string(str)
      self:uint32(#str)
      local buf = ffi.new('uint8_t[?]', #str)
      ffi.copy(buf, str, #str)
      table.insert(self.out, buf)
   end
   function encoder:maybe_string(str)
      if str == nil then
         self:uint32(UINT32_MAX)
      else
         self:string(str)
      end
   end
   function encoder:finish()
      local size = 0
      for _,src in ipairs(self.out) do size = size + ffi.sizeof(src) end
      local dst = ffi.new('uint8_t[?]', size)
      local pos = 0
      for _,src in ipairs(self.out) do
         ffi.copy(dst + pos, src, ffi.sizeof(src))
         pos = pos + ffi.sizeof(src)
      end
      return dst, size
   end
   return encoder
end

function encode_raise_alarm (...)
   local codec = encoder()
   codec:uint32(assert(alarm_codes['raise_alarm']))
   return assert(alarms['raise_alarm'])(codec, ...)
end

function encode_clear_alarm (...)
   local codec = encoder()
   codec:uint32(assert(alarm_codes['clear_alarm']))
   return assert(alarms['clear_alarm'])(codec, ...)
end

function encode_add_to_inventory (...)
   local codec = encoder()
   codec:uint32(assert(alarm_codes['add_to_inventory']))
   return assert(alarms['add_to_inventory'])(codec, ...)
end

function encode_declare_alarm (...)
   local codec = encoder()
   codec:uint32(assert(alarm_codes['declare_alarm']))
   return assert(alarms['declare_alarm'])(codec, ...)
end

local uint32_ptr_t = ffi.typeof('uint32_t*')
local function decoder(buf, len)
   local decoder = { buf=buf, len=len, pos=0 }
   function decoder:read(count)
      local ret = self.buf + self.pos
      self.pos = self.pos + count
      assert(self.pos <= self.len)
      return ret
   end
   function decoder:uint32()
      return ffi.cast(uint32_ptr_t, self:read(4))[0]
   end
   function decoder:string()
      local len = self:uint32()
      return ffi.string(self:read(len), len)
   end
   function decoder:maybe_string()
      local len = self:uint32()
      if len == UINT32_MAX then return nil end
      return ffi.string(self:read(len), len)
   end
   function decoder:finish(...)
      return { ... }
   end
   return decoder
end

function decode(buf, len)
   local codec = decoder(buf, len)
   local name = assert(alarm_names[codec:uint32()])
   return { name, assert(alarms[name], name)(codec) }
end

---

local alarms_channel

function get_channel()
   if alarms_channel then return alarms_channel end
   local name = '/'..S.getpid()..'/alarms-worker-channel'
   local success, value = pcall(channel.open, name)
   if success then
      alarms_channel = value
   else
      alarms_channel = channel.create('alarms-worker-channel', 1e6)
   end
   return alarms_channel
end

local function normalize (t, attrs)
   t = t or {}
   local ret = {}
   for i, k in ipairs(attrs) do ret[i] = t[k] end
   return unpack(ret)
end

local alarm = {
   key_attrs = {'resource', 'alarm_type_id', 'alarm_type_qualifier'},
   args_attrs = {'perceived_severity', 'alarm_text'},
}
function alarm:normalize_key (t)
   return normalize(t, self.key_attrs)
end
function alarm:normalize_args (t)
   return normalize(t, self.args_attrs)
end

-- To be used by the manager to group args into key and args.
function to_alarm (args)
   local key = {
      resource = args[1],
      alarm_type_id = args[2],
      alarm_type_qualifier = args[3],
   }
   local args = {
      perceived_severity = args[4],
      alarm_text = args[5],
   }
   return key, args
end

local alarm_type = {
   key_attrs = {'alarm_type_id', 'alarm_type_qualifier'},
   args_attrs = {'resource', 'has_clear', 'description'},
}
function alarm_type:normalize_key (t)
   return normalize(t, self.key_attrs)
end
function alarm_type:normalize_args (t)
   return normalize(t, self.args_attrs)
end

function to_alarm_type (args)
   local alarm_type_id, alarm_type_qualifier, resource, has_clear, description = unpack(args)
   local key = {
      alarm_type_id = args[1],
      alarm_type_qualifier = args[2],
   }
   local args = {
      resource = args[3],
      has_clear = args[4],
      description = args[5],
   }
   return key, args
end

function raise_alarm (key, args)
   local channel = get_channel()
   if channel then
      local resource, alarm_type_id, alarm_type_qualifier = alarm:normalize_key(key)
      local perceived_severity, alarm_text = alarm:normalize_args(args)
      local buf, len = encode_raise_alarm(
         resource, alarm_type_id, alarm_type_qualifier,
         perceived_severity, alarm_text
      )
      channel:put_message(buf, len)
   end
end

function clear_alarm (key)
   local channel = get_channel()
   if channel then
      local resource, alarm_type_id, alarm_type_qualifier = alarm:normalize_key(key)
      local buf, len = encode_clear_alarm(resource, alarm_type_id, alarm_type_qualifier)
      channel:put_message(buf, len)
   end
end

function add_to_inventory (key, args)
   local channel = get_channel()
   if channel then
      local alarm_type_id, alarm_type_qualifier = alarm_type:normalize_key(key)
      local resource, has_clear, description = alarm_type:normalize_args(args)
      local buf, len = encode_add_to_inventory(
         alarm_type_id, alarm_type_qualifier,
         resource, has_clear, description
      )
      channel:put_message(buf, len)
   end
end

function declare_alarm (key, args)
   local channel = get_channel()
   if channel then
      local resource, alarm_type_id, alarm_type_qualifier = alarm:normalize_key(key)
      local perceived_severity, alarm_text = alarm:normalize_args(args)
      local buf, len = encode_declare_alarm(
         resource, alarm_type_id, alarm_type_qualifier,
         perceived_severity, alarm_text
      )
      channel:put_message(buf, len)
   end
end

function selftest ()
   print('selftest: lib.ptree.alarm_codec')
   local lib = require("core.lib")
   local function test_alarm (name, args)
      local encoded, len
      if name == 'raise_alarm' then
         encoded, len = encode_raise_alarm(unpack(args))
      elseif name == 'clear_alarm' then
         encoded, len = encode_clear_alarm(unpack(args))
      else
         error('not valid alarm name: '..alarm)
      end
      local decoded = decode(encoded, len)
      assert(lib.equal({name, args}, decoded))
   end
   local function test_raise_alarm ()
      local key = {resource='res1', alarm_type_id='type1', alarm_type_qualifier=''}
      local args = {perceived_severity='critical'}

      local resource, alarm_type_id, alarm_type_qualifier = alarm:normalize_key(key)
      local perceived_severity, alarm_text = alarm:normalize_args(args)
      local alarm = {resource, alarm_type_id, alarm_type_qualifier,
                     perceived_severity, alarm_text}

      test_alarm('raise_alarm', alarm)
   end
   local function test_clear_alarm ()
      local key = {resource='res1', alarm_type_id='type1', alarm_type_qualifier=''}
      local resource, alarm_type_id, alarm_type_qualifier = alarm:normalize_key(key)
      local alarm = {resource, alarm_type_id, alarm_type_qualifier}
      test_alarm('clear_alarm', alarm)
   end

   test_raise_alarm()
   test_clear_alarm()

   local a, b = normalize({b='foo'}, {'a', 'b'})
   assert(a == nil and b == 'foo')

   print('selftest: ok')
end
