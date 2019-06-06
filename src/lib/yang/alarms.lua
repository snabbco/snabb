module(..., package.seeall)

local data = require('lib.yang.data')
local lib = require('core.lib')
local util = require('lib.yang.util')
local counter = require("core.counter")

local format_date_as_iso_8601 = util.format_date_as_iso_8601
local parse_date_as_iso_8601 = util.parse_date_as_iso_8601

local alarm_handler
function install_alarm_handler(handler)
   alarm_handler = handler
end

local default_alarm_handler = {}
function default_alarm_handler.raise_alarm(key, args)
end
function default_alarm_handler.clear_alarm(key)
end
function default_alarm_handler.add_to_inventory(key, args)
end
function default_alarm_handler.declare_alarm(key, args)
end

install_alarm_handler(default_alarm_handler)

local control = {
   alarm_shelving = {
      shelf = {}
   }
}

local state = {
   alarm_inventory = {
      alarm_type = {},
   },
   alarm_list = {
      alarm = {},
      number_of_alarms = 0,
   },
   shelved_alarms = {
      shelved_alarms = {}
   },
   notifications = {
      alarm = {},
      alarm_inventory_changed = {},
      operator_action = {}
   }
}

local function clear_notifications ()
   state.notifications.alarm = {}
   state.notifications.alarm_inventory_changed = {}
   state.notifications.operator_action = {}
end

function notifications ()
   local ret = {}
   local notifications = state.notifications
   for k,v in pairs(notifications.alarm) do
      table.insert(ret, v)
   end
   for k,v in pairs(notifications.alarm_inventory_changed) do
      table.insert(ret, v)
   end
   for k,v in pairs(notifications.operator_action) do
      table.insert(ret, v)
   end
   clear_notifications()
   return ret
end

local function table_size (t)
   local size = 0
   for _ in pairs(t) do size = size + 1 end
   return size
end

local function table_is_empty(t)
   for k,v in pairs(t) do return false end
   return true
end

function get_state ()
   -- status-change is stored as an array while according to ietf-alarms schema
   -- it should be a hashmap indexed by time.
   local function index_by_time (status_change)
      local ret = {}
      for _, v in pairs(status_change) do ret[v.time] = v end
      return ret
   end
   local function transform_alarm_list (alarm_list)
      local alarm = alarm_list.alarm
      local ret = {}
      for k,v in pairs(alarm) do
         ret[k] = lib.deepcopy(v)
         ret[k].status_change = index_by_time(ret[k].status_change)
         ret[k].operator_state_change = index_by_time(ret[k].operator_state_change)
      end
      alarm_list.alarm = ret
      return alarm_list
   end
   return {
      alarm_inventory = state.alarm_inventory,
      alarm_list = transform_alarm_list(state.alarm_list),
      summary = {
         alarm_summary = build_summary(state.alarm_list.alarm),
      }
   }
end

function build_summary (alarms)
   local function last_operator_state_change (alarm)
      return alarm.operator_state_change[#alarm.operator_state_change]
   end
   local function state_change (alarm)
      local state_change = last_operator_state_change(alarm)
      return state_change and state_change.state or ''
   end
   local function is_cleared (alarm)
      return alarm.is_cleared
   end
   local function is_cleared_not_closed (alarm)
      return alarm.is_cleared and state_change(alarm) ~= 'closed'
   end
   local function is_cleared_closed (alarm)
      return alarm.is_cleared and state_change(alarm) == 'closed'
   end
   local function is_not_cleared_closed (alarm)
      return not alarm.is_cleared and state_change(alarm) == 'closed'
   end
   local function is_not_cleared_not_closed (alarm)
      return not alarm.is_cleared and state_change(alarm) ~= 'closed'
   end
   local ret = {}
   for key, alarm in pairs(alarms) do
      local severity = alarm.perceived_severity
      local entry = ret[severity]
      if not entry then
         entry = {
             total = 0,
             cleared = 0,
             cleared_not_closed = 0,
             cleared_closed = 0,
             not_cleared_closed = 0,
             not_cleared_not_closed = 0,
         }
      end
      entry.total = entry.total + 1
      if is_cleared(alarm) then
         entry.cleared = entry.cleared + 1
      end
      if is_cleared_not_closed(alarm) then
         entry.cleared_not_closed = entry.cleared_not_closed + 1
      end
      if is_cleared_closed(alarm) then
         entry.cleared_closed = entry.cleared_closed + 1
      end
      if is_not_cleared_closed(alarm) then
         entry.not_cleared_closed = entry.not_cleared_closed + 1
      end
      if is_not_cleared_not_closed(alarm) then
         entry.not_cleared_not_closed = entry.not_cleared_not_closed + 1
      end
      ret[severity] = entry
   end
   if not table_is_empty(state.shelved_alarms.shelved_alarms) then
      ret['shelved_alarms'] = table_size(state.shelved_alarms.shelved_alarms)
   end
   return ret
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
function alarm_type_keys:normalize (key)
   local alarm_type_id = assert(key.alarm_type_id)
   local alarm_type_qualifier = key.alarm_type_qualifier or ''
   return self:fetch(alarm_type_id, alarm_type_qualifier)
end

function add_to_inventory (key, args)
   local key = alarm_type_keys:normalize(key)
   alarm_handler.add_to_inventory(key, args)
   local resource = {args.resource}
   -- Preserve previously defined resources.
   if state.alarm_inventory.alarm_type[key] then
      resource = state.alarm_inventory.alarm_type[key].resource
      table.insert(resource, args.resource)
   end
   state.alarm_inventory.alarm_type[key] = args
   state.alarm_inventory.alarm_type[key].resource = resource
   alarm_inventory_changed()
end


local function new_notification (event, value)
   value = value or {}
   assert(type(value) == "table")
   local ret = {event=event}
   for k,v in pairs(value) do ret[k] = v end
   return ret
end

function alarm_inventory_changed()
   table.insert(state.notifications.alarm_inventory_changed,
                new_notification('alarm-inventory-changed'))
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

-- Contains a table with all the declared alarms.
local alarm_list = {
   list = {},
   defaults = {},
}
function alarm_list:new (key, alarm)
   self.list[key] = alarm
   self:set_defaults_if_any(key)
end
function alarm_list:set_defaults_if_any (key)
   k = alarm_type_keys:normalize(key)
   local default = self.defaults[k]
   if default then
      for k,v in pairs(default) do
         self.list[key][k] = v
      end
   end
end
function add_default (key, args)
   self.defaults[key] = args
end
function alarm_list:lookup (key)
   return self.list[key]
end
function alarm_list:retrieve (key, args)
   local function copy (src, args)
      local ret = {}
      for k,v in pairs(src) do ret[k] = args[k] or v end
      return ret
   end
   local alarm = self:lookup(key)
   if alarm then
      return copy(alarm, args)
   end
end

function default_alarms (alarms)
   for k,v in pairs(alarms) do
      k = alarm_type_keys:normalize(k)
      alarm_list.defaults[k] = v
   end
end

function declare_alarm (key, args)
   key = alarm_keys:normalize(key)
   alarm_handler.declare_alarm(key, args)
   local dst = alarm_list:lookup(key)
   if dst then
      -- Extend or overwrite existing alarm values.
      for k, v in pairs(args) do dst[k] = v end
      alarm_list:new(key, dst)
   else
      alarm_list:new(key, args)
   end
   local alarm = {}
   function alarm:raise (raise_args)
      if raise_args then
         local union = {}
         for k,v in pairs(args) do union[k] = v end
         for k,v in pairs(raise_args) do union[k] = v end
         raise_args = union
      else
         raise_args = args
      end
      alarm_handler.raise_alarm(key, raise_args)
   end
   function alarm:clear ()
      alarm_handler.clear_alarm(key)
   end
   return alarm
end

-- Raise alarm.

-- The entry with latest time-stamp in this list MUST correspond to the leafs
-- 'is-cleared', 'perceived-severity' and 'alarm-text' for the alarm.
-- The time-stamp for that entry MUST be equal to the 'last-changed' leaf.
local function add_status_change (key, alarm, status)
   alarm.status_change = alarm.status_change or {}
   alarm.perceived_severity = status.perceived_severity
   alarm.alarm_text = status.alarm_text
   alarm.last_changed = status.time
   state.alarm_list.last_changed = status.time
   table.insert(alarm.status_change, status)
   add_alarm_notification(key, alarm)
end

function add_alarm_notification (key, alarm)
   local notification = {
      time                 = alarm.time,
      resource             = key.resource,
      alarm_type_id        = key.alarm_type_id,
      alarm_type_qualifier = key.alarm_type_qualifier,
      alt_resource         = alarm.alt_resource,
      perceived_severity   = alarm.perceived_severity,
      alarm_text           = alarm.alarm_text
   }
   state.notifications.alarm[key] = new_notification('alarm-notification', notification)
end

-- Creates a new alarm.
--
-- The alarm is retrieved from the db of predefined alarms. Default values get
-- overridden by args. Additional fields are initialized too and an initial
-- status change is added to the alarm.
local function new_alarm (key, args)
   local ret = assert(alarm_list:retrieve(key, args), 'Not supported alarm')
   local status = {
      time = format_date_as_iso_8601(),
      perceived_severity = args.perceived_severity or ret.perceived_severity,
      alarm_text = args.alarm_text or ret.alarm_text,
   }
   add_status_change(key, ret, status)
   ret.last_changed = assert(status.time)
   ret.time_created = assert(ret.last_changed)
   ret.is_cleared = args.is_cleared
   ret.operator_state_change = {}
   state.alarm_list.number_of_alarms = state.alarm_list.number_of_alarms + 1
   return ret
end

-- Adds alarm to state.alarm_list.
local function create_alarm (key, args)
   local alarm = assert(new_alarm(key, args))
   state.alarm_list.alarm[key] = alarm
end

-- The following state changes creates a new status change:
--   - changed severity (warning, minor, major, critical).
--   - clearance status, this also updates the 'is-cleared' leaf.
--   - alarm text update.
local function needs_status_change (alarm, args)
   if alarm.is_cleared ~= args.is_cleared then
      return true
   elseif args.perceived_severity and
          alarm.perceived_severity ~= args.perceived_severity then
      return true
   elseif args.alarm_text and alarm.alarm_text ~= args.alarm_text then
      return true
   end
   return false
end

-- An alarm gets updated if it needs a status change.  A status change implies
-- to add a new status change to the alarm and update the alarm 'is_cleared'
-- flag.
local function update_alarm (key, alarm, args)
   if needs_status_change(alarm, args) then
      local status = {
         time = assert(format_date_as_iso_8601()),
         perceived_severity = assert(args.perceived_severity or alarm.perceived_severity),
         alarm_text = assert(args.alarm_text or alarm.alarm_text),
      }
      add_status_change(key, alarm, status)
      alarm.is_cleared = args.is_cleared
   end
end

local function is_shelved(key)
   return control.alarm_shelving.shelf[key]
end

-- Check up if the alarm already exists in state.alarm_list.
local function lookup_alarm (key)
   if is_shelved(key) then
      return state.shelved_alarms.shelved_alarms[key]
   else
      return state.alarm_list.alarm[key]
   end
end

-- Notifications are only sent when a new alarm is raised, re-raised after being
-- cleared and when an alarm is cleared.
function raise_alarm (key, args)
   assert(key)
   args = args or {}
   args.is_cleared = false
   key = alarm_keys:normalize(key)
   local alarm = lookup_alarm(key)
   if not alarm then
      create_alarm(key, args)
   else
      update_alarm(key, alarm, args)
   end
end

-- Clear alarm.

function clear_alarm (key)
   assert(key)
   local args = {is_cleared = true}
   key = alarm_keys:normalize(key)
   local alarm = lookup_alarm(key)
   if alarm then
      update_alarm(key, alarm, args)
   end
end

-- Alarm shelving.

function shelve_alarm (key, alarm)
   alarm = alarm or state.alarm_list.alarm[key]
   state.shelved_alarms.shelved_alarms[key] = alarm
   state.alarm_list.alarm[key] = nil
   control.alarm_shelving.shelf[key] = true
end

function unshelve_alarm (key, alarm)
   alarm = alarm or state.shelved_alarms.shelved_alarms[key]
   state.alarm_list.alarm[key] = alarm
   state.shelved_alarms.shelved_alarms[key] = nil
   control.alarm_shelving.shelf[key] = nil
end

-- Set operator state.

local operator_states = lib.set('none', 'ack', 'closed', 'shelved', 'un-shelved')

function set_operator_state (key, args)
   assert(args.state and operator_states[args.state],
          'Not a valid operator state: '..args.state)
   key = alarm_keys:normalize(key)
   local alarm
   if args.state == 'un-shelved' then
      alarm = assert(state.shelved_alarms.shelved_alarms[key], 'Could not locate alarm in shelved-alarms')
      control.alarm_shelving.shelf[key] = nil
   else
      alarm = assert(state.alarm_list.alarm[key], 'Could not locate alarm in alarm-list')
   end
   if not alarm.operator_state_change then
      alarm.operator_state_change = {}
   end
   local time = format_date_as_iso_8601()
   local status = {
      time = time,
      operator = 'admin',
      state = args.state,
      text = args.text,
   }
   table.insert(alarm.operator_state_change, status)
   if args.state == 'shelved' then
      shelve_alarm(key, alarm)
   elseif args.state == 'un-shelved' then
      unshelve_alarm(key, alarm)
   end
   add_operator_action_notification(key, status)
   return true
end

function add_operator_action_notification (key, status)
   local operator_action = state.notifications.operator_action
   operator_action[key] = new_notification('operator-action', status)
end

-- Purge alarms.

local ages = {seconds=1, minutes=60, hours=3600, days=3600*24, weeks=3600*24*7}

local function toseconds (date)
   local function tz_seconds (t)
      if not t.tz_hour then return 0 end
      local sign = t.tz_sign or "+"
      local seconds = tonumber(t.tz_hour) * 3600 + tonumber(t.tz_min) * 60
      return sign == '+' and seconds or seconds*-1
   end
   if type(date) == 'table' then
      assert(date.age_spec and date.value, "Not a valid 'older_than' data type")

      local multiplier = assert(ages[date.age_spec],
                                "Not a valid 'age_spec' value: "..date.age_spec)
      return date.value * multiplier
   elseif type(date) == 'string' then
      local t = parse_date_as_iso_8601(date)
      return os.time(t) + tz_seconds(t)
   else
      error('Wrong data type: '..type(date))
   end
end

-- `purge_alarms` requests the server to delete entries from the alarm list
-- according to the supplied criteria.  Typically it can be used to delete
-- alarms that are in closed operator state and older than a specified time.
-- The number of purged alarms is returned as an output parameter.
--
-- args: {status, older_than, severity, operator_state}
function purge_alarms (args)
   local alarm_list = state.alarm_list
   local alarms = state.alarm_list.alarm
   args.alarm_status = args.alarm_status or 'any'
   local function purge_alarm (key)
      alarms[key] = nil
      alarm_list.number_of_alarms = alarm_list.number_of_alarms - 1
   end
   local function by_status (alarm, args)
      local status = assert(args.alarm_status)
      local alarm_statuses = lib.set('any', 'cleared', 'not-cleared')
      assert(alarm_statuses[status], 'Not a valid status value: '..status)
      if status == 'any' then return true end
      if status == 'cleared' then return alarm.is_cleared end
      if status == 'not-cleared' then return not alarm.is_cleared end
      return false
   end
   local function by_older_than (alarm, args)
      local older_than = assert(args.older_than)
      if type(older_than) == 'string' then
         local age_spec, value = older_than:match("([%w]+):([%d]+)")
         older_than = {value = value, age_spec = age_spec}
      end
      assert(type(older_than) == 'table')
      local alarm_time = toseconds(alarm.time_created)
      local threshold = toseconds(older_than)
      return os.time() - alarm_time >= threshold
   end
   local function by_severity (alarm, args)
      local severity = assert(args.severity)
      if type(severity) == 'string' then
         local sev_spec, value = severity:match("([%w]+):([%w]+)")
         severity = {sev_spec = sev_spec, value = value}
      end
      assert(type(severity) == 'table' and severity.sev_spec and severity.value,
             'Not valid severity data type')
      local severities = {indeterminate=2, minor=3 , warning=4, major=5, critical=6}
      local function tonumber (severity)
         return severities[severity]
      end
      local sev_spec, severity = severity.sev_spec, tonumber(severity.value)
      local alarm_severity = tonumber(alarm.perceived_severity)
      if sev_spec == 'below' then
         return alarm_severity < severity
      elseif sev_spec == 'is' then
         return alarm_severity == severity
      elseif sev_spec == 'above' then
         return alarm_severity > severity
      else
         error('Not valid sev-spec value: '..sev_spec)
      end
      return false
   end
   local function by_operator_state (alarm, args)
      local operator_state = assert(args.operator_state_filter)
      local state, user
      if type(operator_state) == 'string' then
         state, user = operator_state:match("([%w]+):([%w]+)")
         if not state then
            state, user = operator_state, operator_state
         end
         operator_state = {state=state, user=user}
      end
      assert(type(operator_state) == 'table')
      local function tonumber (state)
         return operator_states[state]
      end
      state, user = operator_state.state, operator_state.user
      if state or user then
         for _, state_change in pairs(alarm.operator_state_change or {}) do
            if state and tonumber(state_change.state) == tonumber(state) then
               return true
            elseif user and state_change.user == user then
               return true
            end
         end
      end
      return false
   end
   local args_to_filters = { older_than=by_older_than,
                             severity = by_severity,
                             operator_state_filter = by_operator_state, }
   local filter = {}
   function filter:initialize (args)
      self.args = args
      self.filters = { by_status }
      for name, filter in pairs(args_to_filters) do
         if args[name] then
            table.insert(self.filters, filter)
         end
      end
   end
   function filter:apply (alarm)
      for _, filter in ipairs(self.filters) do
         if not filter(alarm, self.args) then return false end
      end
      return true
   end
   local count = 0
   filter:initialize(args)
   for key, alarm in pairs(alarms) do
      if filter:apply(alarm) then
         purge_alarm(key)
         count = count + 1
      end
   end
   return count
end

local function alarm_key_matches (k1, k2)
   if k1.resource and k1.resource ~= k2.resource then
     return false
   elseif k1.alarm_type_id and k1.alarm_type_id ~= k2.alarm_type_id then
     return false
   elseif k1.alarm_type_qualifier and
          k1.alarm_type_qualifier ~= k2.alarm_type_qualifier then
     return false
   end
   return true
end

local function compress_alarm (alarm)
   assert(alarm.status_change)
   local latest_status_change = alarm.status_change[#alarm.status_change]
   alarm.status_change = {latest_status_change}
end

-- This operation requests the server to compress entries in the
-- alarm list by removing all but the latest state change for all
-- alarms.  Conditions in the input are logically ANDed.  If no
-- input condition is given, all alarms are compressed.
function compress_alarms (key)
   assert(type(key) == 'table')
   local count = 0
   for k, alarm in pairs(state.alarm_list.alarm) do
      if alarm_key_matches(key, k) then
         compress_alarm(alarm)
         count = count + 1
      end
   end
   return count
end

local Alarm = {}
Alarm.__index={Alarm}

function Alarm:check ()
   if self.next_check == nil then
      self.next_check = engine.now() + self.period
      self.last_value = self:get_value()
   elseif self.next_check < engine.now() then
      local value = self:get_value()
      if (value - self.last_value > self.limit) then
         self.alarm:raise()
      else
         self.alarm:clear()
      end
      self.next_check = engine.now() + self.period
      self.last_value = value
   end
end

CallbackAlarm = {}

function CallbackAlarm.new (alarm, period, limit, expr)
   assert(type(expr) == 'function')
   return setmetatable({alarm=alarm, period=period, limit=limit, expr=expr},
      {__index = setmetatable(CallbackAlarm, {__index=Alarm})})
end
function CallbackAlarm:get_value()
   return self.expr()
end

CounterAlarm = {}

function CounterAlarm.new (alarm, period, limit, object, counter_name)
   return setmetatable({alarm=alarm, period=period, limit=limit,  object=object,
      counter_name=counter_name}, {__index = setmetatable(CounterAlarm, {__index=Alarm})})
end
function CounterAlarm:get_value()
   return counter.read(self.object.shm[self.counter_name])
end

--

function selftest ()
   print("selftest: alarms")
   local function sleep (seconds)
      os.execute("sleep "..tonumber(seconds))
   end
   local function check_status_change (alarm)
      local status_change = alarm.status_change
      for k, v in pairs(status_change) do
         assert(v.perceived_severity)
         assert(v.time)
         assert(v.alarm_text)
      end
   end

   -- ARP alarm.
   add_to_inventory({alarm_type_id='arp-resolution'}, {
      resource='nic-v4',
      has_clear=true,
      description='Raise up if ARP app cannot resolve IP address',
   })
   declare_alarm({resource='nic-v4', alarm_type_id='arp-resolution'}, {
      perceived_severity = 'critical',
      alarm_text = 'Make sure you can ARP resolve IP addresses on NIC',
      alt_resource={'nic-v4-2'},
   })
   -- NDP alarm.
   add_to_inventory({alarm_type_id='ndp-resolution'}, {
      resource='nic-v6',
      has_clear=true,
      description='Raise up if NDP app cannot resolve IP address',
   })
   declare_alarm({resource='nic-v6', alarm_type_id='ndp-resolution'}, {
      perceived_severity = 'critical',
      alarm_text = 'Make sure you can NDP resolve IP addresses on NIC',
   })

   -- Check alarm inventory has been loaded.
   assert(table_size(state.alarm_inventory.alarm_type) > 0)

   -- Check number of alarms is zero.
   assert(state.alarm_list.number_of_alarms == 0)

   -- Raising an alarm when alarms is empty, creates an alarm.
   local key = alarm_keys:fetch('nic-v4', 'arp-resolution')
   raise_alarm(key)
   local alarm = assert(state.alarm_list.alarm[key])
   assert(#alarm.alt_resource == 1)
   assert(alarm.alt_resource[1] == 'nic-v4-2')
   assert(table_size(alarm.status_change) == 1)
   assert(state.alarm_list.number_of_alarms == 1)

   -- Raise same alarm again. Since there are not changes, everything remains the same.
   local alarm = state.alarm_list.alarm[key]
   local last_changed = alarm.last_changed
   local number_of_status_change = table_size(alarm.status_change)
   local number_of_alarms = state.alarm_list.number_of_alarms
   sleep(1)
   raise_alarm(key)
   assert(state.alarm_list.alarm[key].last_changed == last_changed)
   assert(table_size(alarm.status_change) == number_of_status_change)
   assert(state.alarm_list.number_of_alarms == number_of_alarms)

   -- Raise alarm again but changing severity.
   local alarm = state.alarm_list.alarm[key]
   local last_changed = alarm.last_changed
   local number_of_status_change = table_size(alarm.status_change)
   raise_alarm(key, {perceived_severity='minor'})
   assert(alarm.perceived_severity == 'minor')
   assert(last_changed ~= alarm.last_changed)
   assert(table_size(alarm.status_change) == number_of_status_change + 1)
   check_status_change(alarm)

   -- Raise alarm again with same severity. Should not produce changes.
   local alarm = state.alarm_list.alarm[key]
   local last_changed = alarm.last_changed
   local number_of_status_change = table_size(alarm.status_change)
   raise_alarm(key, {perceived_severity='minor'})
   assert(alarm.perceived_severity == 'minor')
   assert(last_changed == alarm.last_changed)
   assert(table_size(alarm.status_change) == number_of_status_change)

   -- Raise alarm again but changing alarm_text. A new status change is added.
   local alarm = state.alarm_list.alarm[key]
   local number_of_status_change = table_size(alarm.status_change)
   raise_alarm(key, {alarm_text='new text'})
   assert(table_size(alarm.status_change) == number_of_status_change + 1)
   assert(alarm.alarm_text == 'new text')

   -- Clear alarm. Should clear alarm and create a new status change in the alarm.
   local alarm = state.alarm_list.alarm[key]
   local number_of_status_change = table_size(alarm.status_change)
   assert(not alarm.is_cleared)
   sleep(1)
   clear_alarm(key)
   assert(alarm.is_cleared)
   assert(table_size(alarm.status_change) == number_of_status_change + 1)

   -- Clear alarm again. Nothing should change.
   local alarm = state.alarm_list.alarm[key]
   local last_changed = alarm.last_changed
   local number_of_status_change = table_size(alarm.status_change)
   assert(alarm.is_cleared)
   clear_alarm(key)
   assert(alarm.is_cleared)
   assert(table_size(alarm.status_change) == number_of_status_change,
          table_size(alarm.status_change).." == "..number_of_status_change)
   assert(alarm.last_changed == last_changed)

   -- Set operator state change.
   assert(table_size(alarm.operator_state_change) == 0)
   set_operator_state(key, {state='ack'})
   assert(table_size(alarm.operator_state_change) == 1)

   -- Set operator state change again. Should create a new operator state change.
   sleep(1)
   set_operator_state(key, {state='ack'})
   assert(table_size(alarm.operator_state_change) == 2)

   -- Summary.
   local t = build_summary(state.alarm_list.alarm)
   assert(t.minor.cleared == 1)
   assert(t.minor.cleared_closed == 0)
   assert(t.minor.cleared_not_closed == 1)
   assert(t.minor.not_cleared_closed == 0)
   assert(t.minor.not_cleared_not_closed == 0)
   assert(t.minor.total == 1)

   -- Compress alarms.
   local key = alarm_keys:fetch('nic-v4', 'arp-resolution')
   local alarm = state.alarm_list.alarm[key]
   assert(table_size(alarm.status_change) == 4)
   compress_alarms({resource='nic-v4'})
   assert(table_size(alarm.status_change) == 1)

   -- Set operator state change on non existent alarm should fail.
   local key = {resource='none', alarm_type_id='none', alarm_type_qualifier=''}
   local success = pcall(set_operator_state, key, {state='ack'})
   assert(not success)

   -- Test toseconds.
   assert(toseconds({age_spec='weeks', value=1}) == 3600*24*7)
   local now = os.time()
   assert(now == toseconds(format_date_as_iso_8601(now)),
          now.." != "..toseconds(format_date_as_iso_8601(now)))

   -- Purge alarms by status.
   assert(table_size(state.alarm_list.alarm) == 1)
   assert(purge_alarms({alarm_status = 'any'}) == 1)
   assert(table_size(state.alarm_list.alarm) == 0)
   assert(purge_alarms({alarm_status = 'any'}) == 0)

   -- Purge alarms filtering by older_than.
   local key = alarm_keys:fetch('nic-v4', 'arp-resolution')
   raise_alarm(key)
   sleep(1)
   assert(purge_alarms({older_than={age_spec='seconds', value='1'}}) == 1)

   -- Purge alarms by severity.
   local key = alarm_keys:fetch('nic-v4', 'arp-resolution')
   raise_alarm(key)
   assert(table_size(state.alarm_list.alarm) == 1)
   assert(purge_alarms({severity={sev_spec='is', value='minor'}}) == 0)
   assert(purge_alarms({severity={sev_spec='below', value='minor'}}) == 0)
   assert(purge_alarms({severity={sev_spec='above', value='minor'}}) == 1)

   raise_alarm(key, {perceived_severity='minor'})
   assert(purge_alarms({severity={sev_spec='is', value='minor'}}) == 1)

   raise_alarm(alarm_keys:fetch('nic-v4', 'arp-resolution'))
   raise_alarm(alarm_keys:fetch('nic-v6', 'ndp-resolution'))
   assert(table_size(state.alarm_list.alarm) == 2)
   assert(purge_alarms({severity={sev_spec='above', value='minor'}}) == 2)

   -- Purge alarms by operator_state_filter.
   local key = alarm_keys:fetch('nic-v4', 'arp-resolution')
   raise_alarm(key)
   assert(table_size(state.alarm_list.alarm) == 1)
   local success = set_operator_state(key, {state='ack'})
   assert(success)
   local alarm = assert(state.alarm_list.alarm[key])
   assert(table_size(alarm.operator_state_change) == 1)
   assert(purge_alarms({operator_state_filter={state='ack'}}) == 1)

   -- Shelving and alarm should:
   -- - Add shelving criteria to alarms/control.
   -- - Move alarm from alarms/alarm-list to alarms/shelved-alarms.
   -- - Do not generate notifications if the alarm changes its status.
   -- - Increase the number of shelved alarms in summary.
   local key = alarm_keys:fetch('nic-v4', 'arp-resolution')
   raise_alarm(key, {perceived_severity='minor'})
   local success = set_operator_state(key, {state='shelved'})
   assert(success)
   assert(table_size(control.alarm_shelving.shelf) == 1)
   assert(table_size(state.shelved_alarms.shelved_alarms) == 1)

   -- Changing alarm status should create a new status in shelved alarm.
   alarm = state.shelved_alarms.shelved_alarms[key]
   assert(table_size(alarm.status_change) == 1)
   raise_alarm(key, {perceived_severity='critical'})
   assert(table_size(state.alarm_list.alarm) == 0)
   assert(table_size(alarm.status_change) == 2)

   -- Un-shelving and alarm should:
   -- - Remove shelving criteria from alarms/control.
   -- - Move alarm from alarms/shelved-alarms to alarms/alarm-list.
   -- - The alarm now generates notifications if it changes its status.
   -- - Decrease the number of shelved alarms in summary.
   local success = set_operator_state(key, {state='un-shelved'})
   assert(success)
   assert(table_size(control.alarm_shelving.shelf) == 0)
   raise_alarm(key, {perceived_severity='critical'})
   assert(not state.shelved_alarms.shelved_alarms[key])
   assert(state.alarm_list.alarm[key])

   print("ok")
end
