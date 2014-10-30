module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

-- Mark app as dead (record time and cause of death).
local function mark_dead (app, err)
   app.dead = { error = err, time = C.get_monotonic_time() }
end

-- Run app:methodname() in protected mode (pcall). If it throws an error
-- app will be marked as dead and restarted eventually.
function with_restart (app, methodname)
   -- Run app:methodname() in protected mode using pcall.
   local status, err = pcall(app[methodname], app)
   -- If pcall caught an error mark app as "dead".
   if not status then mark_dead(app, err) end
   return status
end

-- Run timer in protected mode (pcall). If it throws an error the app
-- owning timer will be marked as dead and restarted eventually.
function with_restart_timer (timer)
   -- Run timer in protected mode using pcall.
   local status, err = pcall(timer.fn, timer)
   err = ("%s: %s"):format(timer.name, err)
   -- If pcall caught an error mark app owning (if any) timer as "dead".
   if not status then
      if timer.app then mark_dead(timer.app, err)
      else print(err) end
   end
   return status
end

-- Compute actions to restart dead apps in app_array.
function compute_restart_actions (app_array)
   local restart_delay = 2 -- seconds
   local actions = { start={}, restart={}, reconfig={}, keep={}, stop={} }
   local restart = false
   local now = C.get_monotonic_time()
   -- Collect 'restart' actions for dead apps and log their errors.
   for i = 1, #app_array do
      local app = app_array[i]
      if app.dead and (now - app.dead.time) >= restart_delay then
         restart = true
         print(("Restarting %s (died at %f: %s)")
               :format(app.name, app.dead.time, app.dead.error))
         table.insert(actions.restart, app.name)
      else
         table.insert(actions.keep, app.name)
      end
   end
   -- Return actions if any restarts are required, otherwise return nil.
   if restart then return actions
   else return nil end
end
