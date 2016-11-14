-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local S = require("syscall")
local lib = require("core.lib")
local ffi = require("ffi")
local yang = require("lib.yang.yang")
local binary = require("lib.yang.binary")
local shm = require("core.shm")

local action_names = { 'unlink_output', 'unlink_input', 'free_link',
                       'new_link', 'link_output', 'link_input', 'stop_app',
                       'start_app', 'reconfig_app' }
local action_codes = {}
for i, name in ipairs(action_names) do action_codes[name] = i end

local actions = {}

function actions.unlink_output (codec, appname, linkname)
   codec:string(appname)
   codec:string(linkname)
end
function actions.unlink_input (codec, appname, linkname)
   codec:string(appname)
   codec:string(linkname)
end
function actions.free_link (codec, linkspec)
   codec:string(linkspec)
end
function actions.new_link (codec, linkspec)
   codec:string(linkspec)
end
function actions.link_output (codec, appname, linkname, linkspec)
   codec:string(appname)
   codec:string(linkname)
   codec:string(linkspec)
end
function actions.link_input (codec, appname, linkname, linkspec)
   codec:string(appname)
   codec:string(linkname)
   codec:string(linkspec)
end
function actions.stop_app (codec, name)
   codec:string(name)
end
function actions.start_app (codec, name, class, arg)
   codec:string(name)
   codec:class(class)
   codec:config(class, arg)
end
function actions.reconfig_app (codec, name, class, arg)
   codec:string(name)
   codec:config(class, arg)
end

local public_names = {}
local function find_public_name(obj)
   if public_names[obj] then return unpack(public_names[obj]) end
   for modname, mod in pairs(package.loaded) do
      for name, val in pairs(mod) do
         if val == obj then
            if type(val) == 'table' and type(val.new) == 'function' then
               public_names[obj] = { modname, name }
               return modname, name
            end
         end
      end
   end
   error('could not determine public name for object: '..tostring(obj))
end

local lower_case = "abcdefghijklmnopqrstuvwxyz"
local upper_case = lower_case:upper()
local extra = "0123456789_-"
local alphabet = table.concat({lower_case, upper_case, extra})
assert(#alphabet == 64)
local function random_file_name()
   local f = io.open('/dev/urandom', 'rb')
   -- 22 bytes, but we only use 2^6=64 bits from each byte, so total of
   -- 132 bits of entropy.
   local bytes = f:read(22)
   assert(#bytes == 22)
   f:close()
   local out = {}
   for i=1,#bytes do
      table.insert(out, alphabet:byte(bytes:byte(i) % 64 + 1))
   end
   local basename = string.char(unpack(out))
   return shm.root..'/'..tostring(S.getpid())..'/app-conf-'..basename
end

local function encoder()
   local encoder = { out = {} }
   function encoder:uint32(len)
      table.insert(self.out, ffi.new('uint32_t[1]', len))
   end
   function encoder:string(str)
      self:uint32(#str)
      table.insert(self.out, ffi.new('uint8_t[?]', #str, str))
   end
   function encoder:class(class)
      local require_path, name = find_public_name(class)
      encoder:string(require_path)
      encoder:string(name)
   end
   function encoder:config(class, arg)
      local file_name = random_file_name()
      if class.yang_schema then
         yang.compile_data_for_schema_by_name(class.yang_schema, arg,
                                              file_name)
      else
         binary.compile_ad_hoc_lua_data_to_file(file_name, arg)
      end
      encoder:string(file_name)
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
      return dst
   end
   return encoder
end

local function encode_action(action)
   local name, args = unpack(action)
   local codec = encoder()
   codec:uint32(assert(action_codes[name], name))
   assert(actions[name], name)(codec, unpack(args))
   return codec:finish()
end

function selftest ()
   print('selftest: apps.config.action_queue')
   local function serialize(data)
      local tmp = random_file_name()
      print('serializing to:', tmp)
      binary.compile_ad_hoc_lua_data_to_file(tmp, data)
      local loaded = binary.load_compiled_data_file(tmp)
      assert(loaded.schema_name == '')
      assert(lib.equal(data, loaded.data))
      os.remove(tmp)
   end
   serialize('foo')
   serialize({foo='bar'})
   serialize({foo={qux='baz'}})
   serialize(1)
   serialize(1LL)
   local appname, linkname, linkspec = 'foo', 'bar', 'foo.a -> bar.q'
   local class, arg = require('apps.basic.basic_apps').Tee, {}
   encode_action({'unlink_output', {appname, linkname}})
   encode_action({'unlink_input', {appname, linkname}})
   encode_action({'free_link', {linkspec}})
   encode_action({'new_link', {linkspec}})
   encode_action({'link_output', {appname, linkname, linkspec}})
   encode_action({'link_input', {appname, linkname, linkspec}})
   encode_action({'stop_app', {appname}})
   encode_action({'start_app', {appname, class, arg}})
   encode_action({'reconfig_app', {appname, class, arg}})
   print('selftest: ok')
end
