module(..., package.seeall)

local data = require('lib.yang.data')
local util = require('lib.yang.util')
local alarm_codec = require('apps.config.alarm_codec')

local state = {
   alarm_inventory = {
      alarm_type = {},
   },
}

function get_state ()
   return {
      alarm_inventory = state.alarm_inventory,
   }
end

-- Single point to access alarm type keys.
alarm_type_keys = {}

function alarm_type_keys:fetch (alarm_type_id, alarm_type_qualifier)
   self.cache = self.cache or {}
   local function lookup (alarm_type_id, alarm_type_qualifier)
      if not self.cache[alarm_type_id] then
         self.cache[alarm_type_id] = {}
      end
      return self.cache[alarm_type_id][alarm_type_qualifier]
   end
   assert(alarm_type_id)
   alarm_type_qualifier = alarm_type_qualifier or ''
   local key = lookup(alarm_type_id, alarm_type_qualifier)
   if not key then
      key = {alarm_type_id=alarm_type_id, alarm_type_qualifier=alarm_type_qualifier}
      self.cache[alarm_type_id][alarm_type_qualifier] = key
   end
   return key
end

function add_to_inventory (alarm_types)
   for k,v in pairs(alarm_types) do
      local key = alarm_type_keys:fetch(k.alarm_type_id, k.alarm_type_qualifier)
      state.alarm_inventory.alarm_type[key] = v
   end
end

-- Single point to access alarm keys.
alarm_keys = {}

function alarm_keys:fetch (...)
   self.cache = self.cache or {}
   local function lookup (resource, alarm_type_id, alarm_type_qualifier)
      if not self.cache[resource] then
         self.cache[resource] = {}
      end
      if not self.cache[resource][alarm_type_id] then
         self.cache[resource][alarm_type_id] = {}
      end
      return self.cache[resource][alarm_type_id][alarm_type_qualifier]
   end
   local resource, alarm_type_id, alarm_type_qualifier = unpack({...})
   assert(resource and alarm_type_id)
   alarm_type_qualifier = alarm_type_qualifier or ''
   local key = lookup(resource, alarm_type_id, alarm_type_qualifier)
   if not key then
      key = {resource=resource, alarm_type_id=alarm_type_id,
             alarm_type_qualifier=alarm_type_qualifier}
      self.cache[resource][alarm_type_id][alarm_type_qualifier] = key
   end
   return key
end
function alarm_keys:normalize (key)
   local resource = assert(key.resource)
   local alarm_type_id = assert(key.alarm_type_id)
   local alarm_type_qualifier = key.alarm_type_qualifier or ''
   return self:fetch(resource, alarm_type_id, alarm_type_qualifier)
end

local function table_size (t)
   local size = 0
   for _ in pairs(t) do size = size + 1 end
   return size
end

-- Contains a table with all the declared alarms.
local alarm_list = {}

function declare_alarm (alarm)
   assert(table_size(alarm) == 1)
   local key
   for k, v in pairs(alarm) do
      key = alarm_keys:normalize(k)
      alarm_list[key] = v
   end
   function alarm:raise (args)
      alarm_codec.raise_alarm(key, args)
   end
   function alarm:clear ()
      alarm_codec.clear_alarm(key)
   end
   return alarm
end

---

function raise_alarm (key, args)
   print('raise_alarm')
   assert(type(key) == 'table')
   assert(type(args) == 'table')
end

function clear_alarm (key)
   print('clear alarm')
   assert(type(key) == 'table')
end

---

function selftest ()
   print("selftest: alarms")

   require("apps.ipv4.arp")
   assert(table_size(state.alarm_inventory.alarm_type) > 0)

   print("ok")
end
