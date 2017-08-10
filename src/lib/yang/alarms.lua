module(..., package.seeall)

local data = require('lib.yang.data')
local util = require('lib.yang.util')

local state = {
   alarm_inventory = {},
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

local function load_default_configuration ()
   local content = require("apps.lwaftr.alarms.lwaftr_default_alarms.inc")
   local conf = data.load_state_for_schema_by_name('ietf-alarms', content)
   return conf.alarms
end

local default = load_default_configuration()
state.alarm_inventory = default.alarm_inventory

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
   local function table_size (t)
      local size = 0
      for _ in pairs(t) do size = size + 1 end
      return size
   end

   assert(table_size(state.alarm_inventory.alarm_type) > 0)

   print("ok")
end
