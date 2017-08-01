-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local S = require("syscall")
local channel = require("apps.config.channel")
local ffi = require("ffi")

local alarm_names = { 'raise_alarm', 'clear_alarm' }
local alarm_codes = {}
for i, name in ipairs(alarm_names) do alarm_codes[name] = i end

local alarms = {}

function alarms.raise_alarm (codec, resource, alarm_type_id, alarm_type_qualifier,
   perceived_severity, alarm_text)

   local resource = codec:string(resource)
   local alarm_type_id = codec:string(alarm_type_id)
   local alarm_type_qualifier = codec:string(alarm_type_qualifier)

   local perceived_severity = codec:string(perceived_severity)
   local alarm_text = codec:string(alarm_text)

   return codec:finish(resource, alarm_type_id, alarm_type_qualifier,
                       perceived_severity, alarm_text)
end
function alarms.clear_alarm (codec, resource, alarm_type_id, alarm_type_qualifier)
   local resource = codec:string(resource)
   local alarm_type_id = codec:string(alarm_type_id)
   local alarm_type_qualifier = codec:string(alarm_type_qualifier)

   return codec:finish(resource, alarm_type_id, alarm_type_qualifier)
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

function encode(alarm)
   local name, args = unpack(alarm)
   local codec = encoder()
   codec:uint32(assert(alarm_codes[name], name))
   return assert(alarms[name], name)(codec, unpack(args))
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
   local name = '/'..S.getpid()..'/alarms-follower-channel'
   local success, value = pcall(channel.open, name)
   if success then
      alarms_channel = value
   else
      alarms_channel = channel.create('alarms-follower-channel', 1e6)
   end
   return alarms_channel
end

local key_attrs = {'resource', 'alarm_type_id', 'alarm_type_qualifier'}
local args_attrs = {'perceived_severity', 'alarm_text'}
local function normalize (t, attrs)
   t = t or {}
   local ret = {}
   for _, k in ipairs(attrs) do
      table.insert(ret, t[k] or '')
   end
   return ret
end
local function normalize_key (t)
   return normalize(t, key_attrs)
end
local function normalize_args (t)
   return normalize(t, args_attrs)
end

-- To be used by the leader to group args into key and args.
function parse_args (args)
   local resource, alarm_type_id, alarm_type_qualifier, perceived_severity, alarm_text = unpack(args)
   local key = {
      resource = resource,
      alarm_type_id = alarm_type_id,
      alarm_type_qualifier = alarm_type_qualifier,
   }
   local args = {
      perceived_severity = perceived_severity,
      alarm_text = alarm_text,
   }
   return key, args
end

function raise_alarm (key, args)
   local channel = get_channel()
   if channel then
      local resource, alarm_type_id, alarm_type_qualifier = unpack(normalize_key(key))
      local perceived_severity, alarm_text = unpack(normalize_args(args))
      local buf, len = encode({'raise_alarm', {
         resource, alarm_type_id, alarm_type_qualifier,
         perceived_severity, alarm_text,
      }})
      channel:put_message(buf, len)
   end
end

function clear_alarm (key)
   local channel = get_channel()
   if channel then
      local resource, alarm_type_id, alarm_type_qualifier = unpack(normalize_key(key))
      local buf, len = encode({'clear_alarm', {
         resource, alarm_type_id, alarm_type_qualifier
      }})
      channel:put_message(buf, len)
   end
end

function selftest ()
   print('selftest: apps.config.alarm_codec')
   local lib = require("core.lib")
   local function test_alarm(alarm)
      local encoded, len = encode(alarm)
      local decoded = decode(encoded, len)
      assert(lib.equal(alarm, decoded))
   end
   local function test_raise_alarm ()
      local key = {resource='res1'}
      local args = {perceived_severity='critical'}

      local resource, alarm_type_id, alarm_type_qualifier = unpack(normalize_key(key))
      local perceived_severity, alarm_text = unpack(normalize_args(args))

      local alarm = {'raise_alarm', {resource, alarm_type_id, alarm_type_qualifier,
                                     perceived_severity, alarm_text}}
      test_alarm(alarm)
   end
   local function test_clear_alarm ()
      local key = {resource='res1'}
      local resource, alarm_type_id, alarm_type_qualifier = unpack(normalize_key(key))
      local alarm = {'clear_alarm', {resource, alarm_type_id, alarm_type_qualifier}}
      test_alarm(alarm)
   end

   test_raise_alarm()
   test_clear_alarm()

   print('selftest: ok')
end
