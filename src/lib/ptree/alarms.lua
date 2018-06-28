-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local S = require("syscall")
local mem = require("lib.stream.mem")
local channel = require("lib.ptree.channel")
local ffi = require("ffi")

local uint32_t = ffi.typeof('uint32_t')
local UINT32_MAX = 0xffffffff

local alarm_names = { 'raise_alarm', 'clear_alarm', 'add_to_inventory', 'declare_alarm' }
local alarm_codes = {}
for i, name in ipairs(alarm_names) do alarm_codes[name] = i end

local alarms = {}

function alarms.raise_alarm (codec, resource, alarm_type_id, alarm_type_qualifier,
   perceived_severity, alarm_text, alt_resource)

   local resource = codec:string(resource)
   local alarm_type_id = codec:string(alarm_type_id)
   local alarm_type_qualifier = codec:string(alarm_type_qualifier)

   local perceived_severity = codec:maybe_string(perceived_severity)
   local alarm_text = codec:maybe_string(alarm_text)
   local alt_resource = codec:maybe_string_list(alt_resource)

   return codec:finish(resource, alarm_type_id, alarm_type_qualifier,
                       perceived_severity, alarm_text, alt_resource)
end
function alarms.clear_alarm (codec, resource, alarm_type_id, alarm_type_qualifier)
   local resource = codec:string(resource)
   local alarm_type_id = codec:string(alarm_type_id)
   local alarm_type_qualifier = codec:string(alarm_type_qualifier)

   return codec:finish(resource, alarm_type_id, alarm_type_qualifier)
end
function alarms.add_to_inventory (codec, alarm_type_id, alarm_type_qualifier,
   resource, has_clear, description, alt_resource)

   local alarm_type_id = codec:string(alarm_type_id)
   local alarm_type_qualifier = codec:maybe_string(alarm_type_qualifier)

   local resource = codec:string(resource)
   local has_clear = codec:string((has_clear and "true" or "false"))
   local description = codec:maybe_string(description)
   local alt_resource = codec:maybe_string_list(alt_resource)

   return codec:finish(alarm_type_id, alarm_type_qualifier,
                       resource, has_clear, description, alt_resource)
end
function alarms.declare_alarm (codec, resource, alarm_type_id, alarm_type_qualifier,
   perceived_severity, alarm_text, alt_resource)

   local resource = codec:string(resource)
   local alarm_type_id = codec:string(alarm_type_id)
   local alarm_type_qualifier = codec:maybe_string(alarm_type_qualifier)

   local perceived_severity = codec:maybe_string(perceived_severity)
   local alarm_text = codec:maybe_string(alarm_text)
   local alt_resource = codec:maybe_string_list(alt_resource)


   return codec:finish(resource, alarm_type_id, alarm_type_qualifier,
                       perceived_severity, alarm_text, alt_resource)
end

local Encoder = {}
function Encoder.new()
   return setmetatable({ out = mem.tmpfile() }, {__index=Encoder})
end
function Encoder:reset()
   self.out:seek('set', 0)
end
function Encoder:uint32(len)
   self.out:write_scalar(uint32_t, len)
end
function Encoder:string(str)
   self:uint32(#str)
   self.out:write_chars(str)
end
function Encoder:maybe_string(str)
   if str == nil then
      self:uint32(UINT32_MAX)
   else
      self:string(str)
   end
end
function Encoder:maybe_string_list(list)
   if list == nil or #list == 0 then
      self:uint32(UINT32_MAX)
   else
      self:uint32(#list)
      for _, str in ipairs(list) do
         self:string(str)
      end
   end
end
function Encoder:finish()
   local len = self.out:seek()
   local buf = ffi.new('uint8_t[?]', len)
   self.out:seek('set', 0)
   self.out:read_bytes_or_error(buf, len)
   return buf, len
end

local encoder = Encoder.new()
local encoders = {}
function encoders.raise_alarm (key, args)
   encoder:reset()
   encoder:uint32(alarm_codes.raise_alarm)
   return alarms.raise_alarm(
      encoder,
      key.resource, key.alarm_type_id, key.alarm_type_qualifier,
      args.perceived_severity, args.alarm_text, args.alt_resource)
end

function encoders.clear_alarm (key)
   encoder:reset()
   encoder:uint32(alarm_codes.clear_alarm)
   return alarms.clear_alarm(encoder, key.resource, key.alarm_type_id,
                             key.alarm_type_qualifier)
end

function encoders.add_to_inventory (key, args)
   encoder:reset()
   encoder:uint32(alarm_codes.add_to_inventory)
   return alarms.add_to_inventory(
      encoder,
      key.alarm_type_id, key.alarm_type_qualifier,
      args.resource, args.has_clear, args.description, args.alt_resource)
end

function encoders.declare_alarm (key, args)
   encoder:reset()
   encoder:uint32(alarm_codes.declare_alarm)
   return alarms.declare_alarm(
      encoder,
      key.resource, key.alarm_type_id, key.alarm_type_qualifier,
      args.perceived_severity, args.alarm_text, args.alt_resource)
end

function encode(name, key, args)
   return assert(encoders[name])(key, args)
end

local function decoder(buf, len)
   local decoder = { stream=mem.open(buf, len) }
   function decoder:uint32()
      return self.stream:read_scalar(nil, uint32_t)
   end
   function decoder:string()
      local len = self:uint32()
      return self.stream:read_chars(len)
   end
   function decoder:maybe_string()
      local len = self:uint32()
      if len == UINT32_MAX then return nil end
      return self.stream:read_chars(len)
   end
   function decoder:maybe_string_list()
      local count = self:uint32()
      if count == UINT32_MAX then return nil end
      local out = {}
      for item=1, count do
         table.insert(out, self:string())
      end
      return out
   end
   function decoder:finish(...)
      return { ... }
   end
   return decoder
end

local function to_alarm (args)
   local key = {
      resource = args[1],
      alarm_type_id = args[2],
      alarm_type_qualifier = args[3],
   }
   local args = {
      perceived_severity = args[4],
      alarm_text = args[5],
      alt_resource = args[6],
   }
   return key, args
end
local function to_alarm_type (args)
   local key = {
      alarm_type_id = args[1],
      alarm_type_qualifier = args[2],
   }
   local args = {
      resource = args[3],
      has_clear = args[4],
      description = args[5],
      alt_resource = args[6],
   }
   return key, args
end

local decoders = {
   raise_alarm = to_alarm,
   clear_alarm = to_alarm,
   add_to_inventory = to_alarm_type,
   declare_alarm = to_alarm
}

function decode(buf, len)
   local codec = decoder(buf, len)
   local name = assert(alarm_names[codec:uint32()])
   return name, decoders[name](alarms[name](codec))
end

---

function alarm_handler()
   local success, value = pcall(channel.open, 'alarms-worker-channel')
   local ch = success and value
   if not ch then ch = channel.create('alarms-worker-channel', 1e6) end
   local ret = {}
   function ret.raise_alarm (key, args)
      local buf, len = encoders.raise_alarm(key, args)
      ch:put_message(buf, len)
   end
   function ret.clear_alarm (key)
      local buf, len = encoders.clear_alarm(key)
      ch:put_message(buf, len)
   end
   function ret.add_to_inventory (key, args)
      local buf, len = encoders.add_to_inventory(key, args)
      ch:put_message(buf, len)
   end
   function ret.declare_alarm (key, args)
      local buf, len = encoders.declare_alarm(key, args)
      ch:put_message(buf, len)
   end
   return ret
end

function selftest ()
   print('selftest: lib.ptree.alarms')
   local lib = require("core.lib")
   local function test_alarm (name, key, args)
      local encoded, len = encode(name, key, args)
      local dname, dkey, dargs = decode(encoded, len)
      assert(name == dname)
      assert(lib.equal(key, dkey))
      assert(lib.equal(args or {}, dargs))
   end

   test_alarm('raise_alarm',
              {resource='res1', alarm_type_id='type1', alarm_type_qualifier=''},
              {perceived_severity='critical',
               alarm_text='whoa', alt_resource={'res2a','res2b'}})

   test_alarm('clear_alarm',
              {resource='res1', alarm_type_id='type1', alarm_type_qualifier=''})

   print('selftest: ok')
end
