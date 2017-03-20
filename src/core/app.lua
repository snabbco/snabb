-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local packet    = require("core.packet")
local lib       = require("core.lib")
local link      = require("core.link")
local config    = require("core.config")
local timer     = require("core.timer")
local shm       = require("core.shm")
local histogram = require('core.histogram')
local counter   = require("core.counter")
local zone      = require("jit.zone")
local jit       = require("jit")
local ffi       = require("ffi")
local C         = ffi.C
require("core.packet_h")

-- Packet per pull
pull_npackets = math.floor(link.max / 10)

-- Set to true to enable logging
log = false
local use_restart = false

test_skipped_code = 43

-- The set of all active apps and links in the system, indexed by name.
app_table, link_table = {}, {}

configuration = config.new()

-- Counters for statistics.
breaths   = counter.create("engine/breaths.counter")   -- Total breaths taken
frees     = counter.create("engine/frees.counter")     -- Total packets freed
freebits  = counter.create("engine/freebits.counter")  -- Total packet bits freed (for 10GbE)
freebytes = counter.create("engine/freebytes.counter") -- Total packet bytes freed
configs   = counter.create("engine/configs.counter")   -- Total configurations loaded

-- Breathing regluation to reduce CPU usage when idle by calling usleep(3).
--
-- There are two modes available:
--
--   Hz = <n> means to aim for an exact <n> breaths per second rhythm
--   Hz = false means dynamic adjustment of the breathing interval
--
-- Dynamic adjustment automatically scales the time to sleep between
-- breaths from nothing up to maxsleep (default: 100us). If packets
-- are processed during a breath then the sleep period is halved, and
-- if no packets are processed during a breath then the sleep interval
-- is increased by one microsecond.
--
-- The default is dynamic adjustment which should work well for the
-- majority of cases.

Hz = false
sleep = 0
maxsleep = 100

-- busywait: If true then the engine will poll for new data in a tight
-- loop (100% CPU) instead of sleeping according to the Hz setting.
busywait = false

-- True when the engine is running the breathe loop.
local running = false

-- Return current monotonic time in seconds.
-- Can be used to drive timers in apps.
monotonic_now = false
function now ()
   -- Return cached time only if it is fresh
   return (running and monotonic_now) or C.get_monotonic_time()
end

-- Run app:methodname() in protected mode (pcall). If it throws an
-- error app will be marked as dead and restarted eventually.
function with_restart (app, method)
   local status, result
   if use_restart then
      -- Run fn in protected mode using pcall.
      status, result = pcall(method, app)

      -- If pcall caught an error mark app as "dead" (record time and cause
      -- of death).
      if not status then
         app.dead = { error = result, time = now() }
      end
   else
      status, result = true, method(app)
   end
   return status, result
end

-- Restart dead apps.
function restart_dead_apps ()
   if not use_restart then return end
   local restart_delay = 2 -- seconds
   local actions = { start={}, restart={}, reconfig={}, keep={}, stop={} }
   local restart = false

   for name, app in pairs(app_table) do
      if app.dead and (now() - app.dead.time) >= restart_delay then
         restart = true
         io.stderr:write(("Restarting %s (died at %f: %s)\n")
                         :format(app.appname, app.dead.time, app.dead.error))
         table.insert(actions.restart, app.appname)
      else
         table.insert(actions.keep, app.appname)
      end
   end

   -- Restart dead apps if necessary.
   if restart then apply_config_actions(actions, configuration) end
end

-- Configure the running app network to match new_configuration.
--
-- Successive calls to configure() will migrate from the old to the
-- new app network by making the changes needed.
function configure (new_config)
   local actions = compute_config_actions(configuration, new_config)
   apply_config_actions(actions, new_config)
   configuration = new_config
   counter.add(configs)
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
   local new_app_table, new_link_table = {}, {}
   -- Table of functions that execute config actions
   local ops = {}
   function ops.stop (name)
      if app_table[name].stop then
         app_table[name]:stop()
      end
      if app_table[name].shm then
         shm.delete_frame(app_table[name].shm)
      end
   end
   function ops.keep (name)
      new_app_table[name] = app_table[name]
   end
   function ops.start (name)
      local class = conf.apps[name].class
      local arg = conf.apps[name].arg
      local app = class:new(arg)
      if type(app) ~= 'table' then
         error(("bad return value from app '%s' start() method: %s"):format(
                  name, tostring(app)))
      end
      local zone = app.zone or getfenv(class.new)._NAME or name
      app.appname = name
      app.output = {}
      app.input = {}
      new_app_table[name] = app
      app.zone = zone
      if app.shm then
         app.shm.dtime = {counter, C.get_unix_time()}
         app.shm = shm.create_frame("apps/"..name, app.shm)
      end
   end
   function ops.restart (name)
      ops.stop(name)
      ops.start(name)
   end
   function ops.reconfig (name)
      if app_table[name].reconfig then
         local arg = conf.apps[name].arg
         local app = app_table[name]
         app:reconfig(arg)
         new_app_table[name] = app
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
      local link = link_table[linkspec] or link.new(linkspec)
      -- Add link to apps
      new_app_table[fa].output[fl] = link
      table.insert(new_app_table[fa].output, link)
      new_app_table[ta].input[tl] = link
      table.insert(new_app_table[ta].input, link)
      -- Remember link
      new_link_table[linkspec] = link
   end
   -- Free obsolete links.
   for linkspec, r in pairs(link_table) do
      if not new_link_table[linkspec] then link.free(r, linkspec) end
   end
   -- Commit changes.
   app_table, link_table = new_app_table, new_link_table
   -- Trigger link event for each app.
   for name, app in pairs(app_table) do
      if app.link then app:link() end
   end
   compute_breathe_order ()
end

-- Sort the NODES topologically according to SUCCESSORS via
-- reverse-post-order numbering.  The sort starts with ENTRIES.  This
-- implementation is recursive; we should change it to be iterative
-- instead.
function tsort (nodes, entries, successors)
   local visited = {}
   local post_order = {}
   local maybe_visit
   local function visit(node)
      visited[node] = true
      for succ,_ in pairs(successors[node]) do maybe_visit(succ) end
      table.insert(post_order, node)
   end
   function maybe_visit(node)
      if not visited[node] then visit(node) end
   end
   for node,_ in pairs(entries) do maybe_visit(node) end
   for node,_ in pairs(nodes) do maybe_visit(node) end
   local ret = {}
   while #post_order > 0 do table.insert(ret, table.remove(post_order)) end
   return ret
end

breathe_pull_order = {}
breathe_push_order = {}

-- Sort the links in the app graph, and arrange to run push() on the
-- apps on the receiving ends of those links.  This will run app:push()
-- once for each link, which for apps with multiple links may cause the
-- app's push function to run multiple times in a breath.
function compute_breathe_order ()
   breathe_pull_order, breathe_push_order = {}, {}
   local entries = {}
   local inputs = {}
   local successors = {}
   for _,app in pairs(app_table) do
      if app.pull then
         table.insert(breathe_pull_order, app)
         for _,link in pairs(app.output) do
            entries[link] = true;
            successors[link] = {}
         end
      end
      for _,link in pairs(app.input) do inputs[link] = app end
   end
   for link,app in pairs(inputs) do
      successors[link] = {}
      if not app.pull then
         for _,succ in pairs(app.output) do
            successors[link][succ] = true
            if not successors[succ] then successors[succ] = {}; end
         end
      end
   end
   for link,succs in pairs(successors) do
      for succ,_ in pairs(succs) do
         if not successors[succ] then successors[succ] = {}; end
      end
   end
   local link_order = tsort(inputs, entries, successors)
   local i = 1
   for _,link in ipairs(link_order) do
      if breathe_push_order[#breathe_push_order] ~= inputs[link] then
         table.insert(breathe_push_order, inputs[link])
      end
   end
end

-- Call this to "run snabb switch".
function main (options)
   options = options or {}
   local done = options.done
   local no_timers = options.no_timers
   if options.duration then
      assert(not done, "You can not have both 'duration' and 'done'")
      done = lib.timeout(options.duration)
   end

   local breathe = breathe
   if options.measure_latency or options.measure_latency == nil then
      local latency = histogram.create('engine/latency.histogram', 1e-6, 1e0)
      breathe = latency:wrap_thunk(breathe, now)
   end

   monotonic_now = C.get_monotonic_time()
   repeat
      breathe()
      if not no_timers then timer.run() end
      if not busywait then pace_breathing() end
   until done and done()
   counter.commit()
   if not options.no_report then report(options.report) end
end

local nextbreath
local lastfrees = 0
local lastfreebits = 0
local lastfreebytes = 0
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
   else
      if lastfrees == counter.read(frees) then
         sleep = math.min(sleep + 1, maxsleep)
         C.usleep(sleep)
      else
         sleep = math.floor(sleep/2)
      end
      lastfrees = counter.read(frees)
      lastfreebytes = counter.read(freebytes)
      lastfreebits = counter.read(freebits)
   end
end

function breathe ()
   running = true
   monotonic_now = C.get_monotonic_time()
   -- Restart: restart dead apps
   restart_dead_apps()
   -- Inhale: pull work into the app network
   for i = 1, #breathe_pull_order do
      local app = breathe_pull_order[i]
      if app.pull and not app.dead then
         zone(app.zone)
         with_restart(app, app.pull)
         zone()
      end
   end
   -- Exhale: push work out through the app network
   for i = 1, #breathe_push_order do
      local app = breathe_push_order[i]
      if app.push and not app.dead then
         zone(app.zone)
         with_restart(app, app.push)
         zone()
      end
   end
   counter.add(breaths)
   -- Commit counters at a reasonable frequency
   if counter.read(breaths) % 100 == 0 then counter.commit() end
   running = false
end

function report (options)
   if not options or options.showload then
      report_load()
   end
   if options and options.showlinks then
      report_links()
   end
   if options and options.showapps then
      report_apps()
   end
end

-- Load reporting prints several metrics:
--   time - period of time that the metrics were collected over
--   fps  - frees per second (how many calls to packet.free())
--   fpb  - frees per breath
--   bpp  - bytes per packet (average packet size)
local lastloadreport = nil
local reportedfrees = nil
local reportedfreebits = nil
local reportedfreebytes = nil
local reportedbreaths = nil
function report_load ()
   local frees = counter.read(frees)
   local freebits = counter.read(freebits)
   local freebytes = counter.read(freebytes)
   local breaths = counter.read(breaths)
   if lastloadreport then
      local interval = now() - lastloadreport
      local newfrees   = tonumber(frees - reportedfrees)
      local newbytes   = tonumber(freebytes - reportedfreebytes)
      local newbits    = tonumber(freebits - reportedfreebits)
      local newbreaths = tonumber(breaths - reportedbreaths)
      local fps = math.floor(newfrees/interval)
      local fbps = math.floor(newbits/interval)
      local fpb = math.floor(newfrees/newbreaths)
      local bpp = math.floor(newbytes/newfrees)
      print(("load: time: %-2.2fs  fps: %-9s fpGbps: %-3.3f fpb: %-3s bpp: %-4s sleep: %-4dus"):format(
         interval,
         lib.comma_value(fps),
         fbps / 1e9,
         lib.comma_value(fpb),
         (bpp ~= bpp) and "-" or tostring(bpp), -- handle NaN
         sleep))
   end
   lastloadreport = now()
   reportedfrees = frees
   reportedfreebits = freebits
   reportedfreebytes = freebytes
   reportedbreaths = breaths
end

function report_links ()
   print("link report:")
   local function loss_rate(drop, sent)
      sent = tonumber(sent)
      if not sent or sent == 0 then return 0 end
      return tonumber(drop) * 100 / (tonumber(drop)+sent)
   end
   local names = {}
   for name in pairs(link_table) do table.insert(names, name) end
   table.sort(names)
   for i, name in ipairs(names) do
      l = link_table[name]
      local txpackets = counter.read(l.stats.txpackets)
      local txdrop = counter.read(l.stats.txdrop)
      print(("%20s sent on %s (loss rate: %d%%)"):format(
            lib.comma_value(txpackets), name, loss_rate(txdrop, txpackets)))
   end
end

function report_apps ()
   print ("apps report:")
   for name, app in pairs(app_table) do
      if app.dead then
         print(name, ("[dead: %s]"):format(app.dead.error))
      elseif app.report then
         print(name)
         if use_restart then
            with_restart(app, app.report)
         else
            -- Restarts are disabled, still we want to not die on
            -- errors during app reports, thus this workaround:
            local status, err = pcall(app.report, app)
            if not status then
               print("Warning: "..name.." threw an error during report: "..err)
            end
         end
      end
   end
end

function selftest ()
   print("selftest: app")
   local App = { push = true }
   function App:new () return setmetatable({}, {__index = App}) end
   local c1 = config.new()
   config.app(c1, "app1", App)
   config.app(c1, "app2", App)
   config.link(c1, "app1.x -> app2.x")
   print("empty -> c1")
   configure(c1)
   assert(#breathe_pull_order == 0)
   assert(#breathe_push_order == 1)
   assert(app_table.app1 and app_table.app2)
   local orig_app1 = app_table.app1
   local orig_app2 = app_table.app2
   local orig_link = link_table['app1.x -> app2.x']
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
   assert(#breathe_pull_order == 0)
   assert(#breathe_push_order == 2)
   assert(app_table.app1 ~= orig_app1) -- should be restarted
   assert(app_table.app2 == orig_app2) -- should be the same
   -- tostring() because == does not work on FFI structs?
   assert(tostring(orig_link) == tostring(link_table['app1.x -> app2.x']))
   print("c2 -> c1")
   configure(c1) -- c2 -> c1
   assert(app_table.app1 ~= orig_app1) -- should be restarted
   assert(app_table.app2 == orig_app2) -- should be the same
   assert(#breathe_pull_order == 0)
   assert(#breathe_push_order == 1)
   print("c1 -> empty")
   configure(config.new())
   assert(#breathe_pull_order == 0)
   assert(#breathe_push_order == 0)
   -- Test app arg validation
   local AppC = {
      config = {
         a = {required=true}, b = {default="foo"}
      }
   }
   local c3 = config.new()
   config.app(c3, "app_valid", AppC, {a="bar"})
   assert(not pcall(config.app, c3, "app_invalid", AppC))
   assert(not pcall(config.app, c3, "app_invalid", AppC, {b="bar"}))
   assert(not pcall(config.app, c3, "app_invalid", AppC, {a="bar", c="foo"}))
-- Test app restarts on failure.
   use_restart = true
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
   main({duration = 4, report = {showapps = true}})
   assert(app_table.app1 ~= orig_app1) -- should be restarted
   assert(app_table.app2 ~= orig_app2) -- should be restarted
   assert(app_table.app3 == orig_app3) -- should be the same
   main({duration = 4, report = {showapps = true}})
   assert(app_table.app3 ~= orig_app3) -- should be restarted
end
