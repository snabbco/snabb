-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)
local ffi = require("ffi")
local lib = require("core.lib")
local ctable = require("lib.ctable")
local floor = math.floor

local function lookup_ptr (self, key)
   local hash = self.hash_fn(key)
   local entry = self.entries + floor(hash*self.scale)
   assert(hash == entry.hash)
   return entry
end

local function lookup_ptr_with_default (self, key)
   local hash = self.hash_fn(key)
   local entry =  self.entries + floor(hash*self.scale)
   if hash == entry.hash and self.equal_fn(key, entry.key) then
      return entry
   else
      return self.default_entry
   end
end

local function update (self, key, value)
   local entry = self:lookup_ptr(ffi.cast("uint8_t *", key))
   entry.value = value
   return entry
end

local function guard ()
   error("immutable ctable")
end

local param = {
   retries = { default = 20 },
   steps = { default = 5 },
   scale= { default = 2 },
   key_type = { required = true },
   value_type = { required = true},
   keys = { required = true },
   values = { default = {} },
   default_value = { default = nil }
}

function new (arg)
   local config = lib.parse(arg, param)
   local ctab_arg = {
      key_type = config.key_type,
      value_type = config.value_type,
      initial_size = #config.keys,
      max_occupancy_rate = 0.8,
   }
   
   local ctab
   local null_value = config.value_type()
   for _ = 1, config.steps do
      for _ = 1, config.retries do
         ctab = ctable.new(ctab_arg)
         for i, key in ipairs(config.keys) do
            if config.values[i] then
               ctab:add(key, config.values[i])
            else
               ctab:add(key, null_value)
            end
         end
         
         if ctab.max_displacement == 0 then
            goto done
         end
         
      end
      ctab_arg.initial_size =
         math.ceil(ctab_arg.initial_size * config.scale)
   end
   
   ::done::
   if ctab.max_displacement ~= 0 then
      print("perfect hash not found, using standard table")
   else
      if config.default_value then
         ctab.default_entry = ctab.entry_type()
         ctab.default_entry.value = config.default_value
         ctab.lookup_ptr = lookup_ptr_with_default
      else
         ctab.lookup_ptr = lookup_ptr
      end

      ctab.add = guard
      ctab.update = update
      ctab.remove = guard
      ctab.remove_ptr = guard
      ctab.resize = guard
   end
   
   return ctab
end

function selftest()
   print("selftest: ctable_perfect")

   local key_t = ffi.typeof("uint16_t[1]")
   local value_t = key_t
   local max_nkeys = 50
   for nkeys = 1, max_nkeys do
      local keys, values, default = {}, {}
      
      for i = 1, nkeys do
         local key = key_t(i)
         table.insert(keys, key_t(i))
         table.insert(values, value_t(i))
      end
      
      if math.random() > 0.5 then
         default = value_t(nkeys+1)
      end
      
      local ctab = new({
            key_type = key_t,
            value_type = value_t,
            keys = keys,
            values = values,
            default_value = default })
      
      if ctab.max_displacement == 0 then
         local limit = (not default and nkeys) or nkeys*2
         for i = 1, limit do
            if i <= nkeys then
               local entry = ctab:lookup_ptr(key_t(i))
               assert(entry.value[0] == i)
            else
               local entry = ctab:lookup_ptr(key_t(i))
               assert(entry.value[0] == default[0])
            end
         end
      end
      
   end
   print("selftest: ok")
end
