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
                       'start_app', 'reconfig_app',
                       'call_app_method_with_blob', 'commit', 'shutdown' }
local action_codes = {}
for i, name in ipairs(action_names) do action_codes[name] = i end

local actions = {}

function actions.unlink_output (codec, appname, linkname)
   local appname = codec:string(appname)
   local linkname = codec:string(linkname)
   return codec:finish(appname, linkname)
end
function actions.unlink_input (codec, appname, linkname)
   local appname = codec:string(appname)
   local linkname = codec:string(linkname)
   return codec:finish(appname, linkname)
end
function actions.free_link (codec, linkspec)
   local linkspec = codec:string(linkspec)
   return codec:finish(linkspec)
end
function actions.new_link (codec, linkspec)
   local linkspec = codec:string(linkspec)
   return codec:finish(linkspec)
end
function actions.link_output (codec, appname, linkname, linkspec)
   local appname = codec:string(appname)
   local linkname = codec:string(linkname)
   local linkspec = codec:string(linkspec)
   return codec:finish(appname, linkname, linkspec)
end
function actions.link_input (codec, appname, linkname, linkspec)
   local appname = codec:string(appname)
   local linkname = codec:string(linkname)
   local linkspec = codec:string(linkspec)
   return codec:finish(appname, linkname, linkspec)
end
function actions.stop_app (codec, appname)
   local appname = codec:string(appname)
   return codec:finish(appname)
end
function actions.start_app (codec, appname, class, arg)
   local appname = codec:string(appname)
   local _class = codec:class(class)
   local config = codec:config(class, arg)
   return codec:finish(appname, _class, config)
end
function actions.reconfig_app (codec, appname, class, arg)
   local appname = codec:string(appname)
   local _class = codec:class(class)
   local config = codec:config(class, arg)
   return codec:finish(appname, _class, config)
end
function actions.call_app_method_with_blob (codec, appname, methodname, blob)
   local appname = codec:string(appname)
   local methodname = codec:string(methodname)
   local blob = codec:blob(blob)
   return codec:finish(appname, methodname, blob)
end
function actions.commit (codec)
   return codec:finish()
end
function actions.shutdown (codec)
   return codec:finish()
end

local public_names = {}
local function find_public_name(obj)
   if public_names[obj] then return unpack(public_names[obj]) end
   for modname, mod in pairs(package.loaded) do
      if type(mod) == 'table' then
         if mod == obj and type(mod.new) == 'function' then
            public_names[obj] = { modname, '' }
            return modname, ''
         end
         for name, val in pairs(mod) do
            if val == obj then
               if type(val) == 'table' and type(val.new) == 'function' then
                  public_names[obj] = { modname, name }
                  return modname, name
               end
            end
         end
      end
   end
   error('could not determine public name for object: '..tostring(obj))
end

local function random_file_name()
   local basename = 'app-conf-'..lib.random_printable_string(160)
   return shm.root..'/'..shm.resolve(basename)
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
   function encoder:blob(blob)
      self:uint32(ffi.sizeof(blob))
      table.insert(self.out, blob)
   end
   function encoder:class(class)
      local require_path, name = find_public_name(class)
      self:string(require_path)
      self:string(name)
   end
   function encoder:config(class, arg)
      local ad_hoc_encodable = {
            table=true, cdata=true, number=true, string=true, boolean=true
      }
      local file_name
      if class.yang_schema then
         file_name = random_file_name()
         yang.compile_config_for_schema_by_name(class.yang_schema, arg,
                                                file_name)
      elseif ad_hoc_encodable[type(arg)] then
         file_name = random_file_name()
         binary.compile_ad_hoc_lua_data_to_file(file_name, arg)
      elseif arg == nil then
         file_name = ''
      else
         error("NYI: encoding app arg of type "..type(arg))
      end
      self:string(file_name)
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

function encode(action)
   local name, args = unpack(action)
   local codec = encoder()
   codec:uint32(assert(action_codes[name], name))
   return assert(actions[name], name)(codec, unpack(args))
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
   function decoder:blob()
      local len = self:uint32()
      local blob = ffi.new('uint8_t[?]', len)
      ffi.copy(blob, self:read(len), len)
      return blob
   end
   function decoder:class()
      local require_path, name = self:string(), self:string()
      if #name > 0 then
         return assert(require(require_path)[name])
      else
         return assert(require(require_path))
      end
   end
   function decoder:config()
      local filename = self:string()
      if #filename > 0 then
         local data = binary.load_compiled_data_file(filename).data
         S.unlink(filename)
         return data
      end
   end
   function decoder:finish(...)
      return { ... }
   end
   return decoder
end

function decode(buf, len)
   local codec = decoder(buf, len)
   local name = assert(action_names[codec:uint32()])
   return { name, assert(actions[name], name)(codec) }
end

function selftest ()
   print('selftest: lib.ptree.action_codec')
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
   local function test_action(action)
      local encoded, len = encode(action)
      local decoded = decode(encoded, len)
      assert(lib.equal(action, decoded))
   end
   local appname, linkname, linkspec = 'foo', 'bar', 'foo.a -> bar.q'
   local class, arg = require('apps.basic.basic_apps').Tee, {}
   -- Because lib.equal only returns true when comparing cdata of
   -- exactly the same type, here we have to use uint8_t[?].
   local methodname, blob = 'zog', ffi.new('uint8_t[?]', 3, 1, 2, 3)
   test_action({'unlink_output', {appname, linkname}})
   test_action({'unlink_input', {appname, linkname}})
   test_action({'free_link', {linkspec}})
   test_action({'new_link', {linkspec}})
   test_action({'link_output', {appname, linkname, linkspec}})
   test_action({'link_input', {appname, linkname, linkspec}})
   test_action({'stop_app', {appname}})
   test_action({'start_app', {appname, class, arg}})
   test_action({'reconfig_app', {appname, class, arg}})
   test_action({'call_app_method_with_blob', {appname, methodname, blob}})
   test_action({'commit', {}})
   print('selftest: ok')
end
