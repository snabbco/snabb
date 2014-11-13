module(...,package.seeall)

local buffer   = require("core.buffer")
local packet   = require("core.packet")
local lib      = require("core.lib")
local link     = require("core.link")
local config   = require("core.config")
local restarts = require("core.restarts")
local timer    = require("core.timer")
local zone     = require("jit.zone")
local ffi      = require("ffi")
local C        = ffi.C
require("core.packet_h")

-- Set to true to enable logging
log = false

test_skipped_code = 43

-- The set of all active apps and links in the system.
-- Indexed both by name (in a table) and by number (in an array).
app_table,  app_array  = {}, {}
link_table, link_array = {}, {}

configuration = config.new()

-- Count of the number of breaths taken
breaths = 0
-- Ideal number of breaths per second
Hz = 10000

-- Return current monotonic time in seconds.
-- Can be used to drive timers in apps.
monotonic_now = false
function now ()
   return monotonic_now
end

-- Configure the running app network to match new_configuration.
-- 
-- Successive calls to configure() will migrate from the old to the
-- new app network by making the changes needed.
function configure (new_config)
   local actions = compute_config_actions(configuration, new_config)
   apply_config_actions(actions, new_config)
   configuration = new_config
end

-- Return the configuration actions needed to migrate from old config to new.
--
-- Here is an example return value for a case where two apps must
-- start, one must stop, and one is kept as it is:
--   { start = {'newapp1', 'newapp2'},
--     stop  = {'deadapp1'},
--     keep  = {'oldapp1'},
--     restart = {},
--     reconfig = {}
--   }
function compute_config_actions (old, new)
   local actions = { start={}, restart={}, reconfig={}, keep={}, stop={} }
   for appname, info in pairs(new.apps) do
      local class, arg = info.class, info.arg
      local action = nil
      if not old.apps[appname]                then action = 'start'
      elseif old.apps[appname].class ~= class then action = 'restart'
      elseif not lib.equal(old.apps[appname].arg, arg)
                                              then action = 'reconfig'
      else                                         action = 'keep'  end
      table.insert(actions[action], appname)
   end
   for appname in pairs(old.apps) do
      if not new.apps[appname] then
	 table.insert(actions['stop'], appname)
      end
   end
   return actions
end

-- Update the active app network by applying the necessary actions.
function apply_config_actions (actions, conf)
   -- The purpose of this function is to populate these tables:
   local new_app_table,  new_app_array  = {}, {}
   local new_link_table, new_link_array = {}, {}
   local new_timers = {}
   -- Temporary name->index table for use in link renumbering
   local app_name_to_index = {}
   -- Table of functions that execute config actions
   local ops = {}
   function ops.stop (name)
      if app_table[name].stop then app_table[name]:stop() end
   end
   function ops.keep (name)
      new_app_table[name] = app_table[name]
      table.insert(new_app_array, app_table[name])
      app_name_to_index[name] = #new_app_array
      -- Keep timers owned by app.
      for _, timer in ipairs(timer.timers) do
         if timer.app == app_table[name] then
            table.insert(new_timers, timer)
         end
      end
   end
   function ops.start (name)
      local class = conf.apps[name].class
      local arg = conf.apps[name].arg
      local app = class:new(arg)
      local zone = app.zone or getfenv(class.new)._NAME or name
      app.name = name
      app.output = {}
      app.input = {}
      new_app_table[name] = app
      table.insert(new_app_array, app)
      app_name_to_index[name] = #new_app_array
      app.zone = zone
   end
   function ops.restart (name)
      ops.stop(name)
      ops.start(name)
   end
   function ops.reconfig (name)
      if app_table[name].reconfig then
         app_table[name]:reconfig(config)
      else
         ops.restart(name)
      end
   end
   -- Dispatch actions in a suitable sequence.
   for _, action in ipairs({'stop', 'restart', 'keep', 'reconfig', 'start'}) do
      for _, name in ipairs(actions[action]) do
	 if log and action ~= 'keep' then
            io.write("engine: ", action, " app ", name, "\n") 
         end
	 ops[action](name)
      end
   end
   -- Setup links: create (or reuse) and renumber.
   for linkspec in pairs(conf.links) do
      local fa, fl, ta, tl = config.parse_link(linkspec)
      if not new_app_table[fa] then error("no such app: " .. fa) end
      if not new_app_table[ta] then error("no such app: " .. ta) end
      -- Create or reuse a link and assign/update receiving app index
      local link = link_table[linkspec] or link.new()
      link.receiving_app = app_name_to_index[ta]
      -- Add link to apps
      new_app_table[fa].output[fl] = link
      new_app_table[ta].input[tl] = link
      -- Remember link
      new_link_table[linkspec] = link
      table.insert(new_link_array, link)
   end
   for _, app in ipairs(new_app_array) do
      if app.relink then app:relink() end
   end
   -- keep loose timers.
   for _, timer in ipairs(timer.timers) do
      if not timer.app then table.insert(new_timers, timer) end
   end
   -- commit changes
   app_table, link_table = new_app_table, new_link_table
   app_array, link_array = new_app_array, new_link_array
   timer.timers = new_timers
end

-- Call this to "run snabb switch".
function main (options)
   options = options or {}
   local done = options.done
   local no_timers = options.no_timers
   if options.duration then
      assert(not done, "You can not have both 'duration' and 'done'")
      done = lib.timer(options.duration * 1e9)
   end
   monotonic_now = C.get_monotonic_time()
   repeat
      breathe()
      if not no_timers then timer.run() end
      pace_breathing()
   until done and done()
   if not options.no_report then report(options.report) end
end

local nextbreath
-- Wait between breaths to keep frequency with Hz.
function pace_breathing ()
   if Hz then
      nextbreath = nextbreath or monotonic_now
      local sleep = tonumber(nextbreath - monotonic_now)
      if sleep > 1e-6 then
         C.usleep(sleep * 1e6)
         monotonic_now = C.get_monotonic_time()
      end
      nextbreath = math.max(nextbreath + 1/Hz, monotonic_now)
   end
end

function breathe ()
   monotonic_now = C.get_monotonic_time()
   -- Restart: restart dead apps
   local restart_actions = restarts.compute_restart_actions(app_array)
   if restart_actions then
      apply_config_actions(restart_actions, configuration)
   end
   -- Inhale: pull work into the app network
   for i = 1, #app_array do
      local app = app_array[i]
      if app.pull and not app.dead then
	 zone(app.zone)
	 restarts.with_restart(app, 'pull')
	 zone()
      end
   end
   -- Exhale: push work out through the app network
   local firstloop = true
   repeat
      local progress = false
      -- For each link that has new data, run the receiving app
      for i = 1, #link_array do
         local link = link_array[i]
         if firstloop or link.has_new_data then
            link.has_new_data = false
            local receiver = app_array[link.receiving_app]
            if receiver.push and not receiver.dead then
               zone(receiver.zone)
               restarts.with_restart(receiver, 'push')
               zone()
               progress = true
            end
         end
      end
      firstloop = false
   until not progress  -- Stop after no link had new data
   breaths = breaths + 1
end

function report (options)
   local function loss_rate(drop, sent)
      sent = tonumber(sent)
      if not sent or sent == 0 then return 0 end
      return tonumber(drop) * 100 / sent
   end
   if not options or options.showlinks then
      print("link report")
      for name, l in pairs(link_table) do
         print(("%s sent on %s (loss rate: %d%%))"):format(l.stats.txpackets,
            name, loss_rate(l.stats.txdrop, l.stats.txpackets)))
      end
   end
   if options and options.showapps then
      print ("apps report")
      for name, app in pairs(app_table) do
         if app.dead then
            print (name, ("[dead: %s]"):format(app.dead.error))
         elseif app.report then
            print (name)
            restarts.with_restart(app, 'report')
         end
      end
   end
end

function report_each_app ()
   for i = 1, #app_array do
      if app_array[i].report then
         app_array[i]:report()
      end
   end
end

function selftest ()
   print("selftest: app")
   local App = {}
   function App:new () return setmetatable({}, {__index = App}) end
   local c1 = config.new()
   config.app(c1, "app1", App)
   config.app(c1, "app2", App)
   config.link(c1, "app1.x -> app2.x")
   print("empty -> c1")
   configure(c1)
   assert(#app_array == 2)
   assert(#link_array == 1)
   assert(app_table.app1 and app_table.app2)
   local orig_app1 = app_table.app1
   local orig_app2 = app_table.app2
   local orig_link = link_array[1]
   print("c1 -> c1")
   configure(c1)
   assert(app_table.app1 == orig_app1)
   assert(app_table.app2 == orig_app2)
   local c2 = config.new()
   config.app(c2, "app1", App, "config")
   config.app(c2, "app2", App)
   config.link(c2, "app1.x -> app2.x")
   config.link(c2, "app2.x -> app1.x")
   print("c1 -> c2")
   configure(c2)
   assert(#app_array == 2)
   assert(#link_array == 2)
   assert(app_table.app1 ~= orig_app1) -- should be restarted
   assert(app_table.app2 == orig_app2) -- should be the same
   -- tostring() because == does not work on FFI structs?
   assert(tostring(orig_link) == tostring(link_table['app1.x -> app2.x']))
   print("c2 -> c1")
   configure(c1) -- c2 -> c1
   assert(app_table.app1 ~= orig_app1) -- should be restarted
   assert(app_table.app2 == orig_app2) -- should be the same
   assert(#app_array == 2)
   assert(#link_array == 1)
   print("c1 -> empty")
   configure(config.new())
   assert(#app_array == 0)
   assert(#link_array == 0)
   -- Test app restarts on failure.
   print("c_fail")
   local App1 = {zone="test"}
   function App1:new () return setmetatable({}, {__index = App1}) end
   function App1:pull () error("Pull error.") end
   function App1:push () return true end
   function App1:report () return true end
   local App2 = {zone="test"}
   function App2:new () return setmetatable({}, {__index = App2}) end
   function App2:pull () return true end
   function App2:push () error("Push error.") end
   function App2:report () return true end
   local App3 = {zone="test"}
   function App3:new () return setmetatable({}, {__index = App3}) end
   function App3:pull () return true end
   function App3:push () return true end
   function App3:report () error("Report error.") end
   local c_fail = config.new()
   config.app(c_fail, "app1", App1)
   config.app(c_fail, "app2", App2)
   config.app(c_fail, "app3", App3)
   config.link(c_fail, "app1.x -> app2.x")
   configure(c_fail)
   local orig_app1 = app_table.app1
   local orig_app2 = app_table.app2
   local orig_app3 = app_table.app3
   local orig_link1 = link_array[1]
   local orig_link2 = link_array[2]
   main({duration = 4, report = {showapps = true}})
   assert(app_table.app1 ~= orig_app1) -- should be restarted
   assert(app_table.app2 ~= orig_app2) -- should be restarted
   assert(app_table.app3 == orig_app3) -- should be the same
   main({duration = 4, report = {showapps = true}})
   assert(app_table.app3 ~= orig_app3) -- should be restarted
   print("OK")
end

-- XXX add graphviz() function back.

