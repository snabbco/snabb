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
local jit       = require("jit")
local S         = require("syscall")
local ffi       = require("ffi")
local C         = ffi.C
require("core.packet_h")

-- Packet per pull
pull_npackets = math.floor(link.max / 10)

-- Set to true to enable logging
log = false
local use_restart = false

test_skipped_code = 43

-- Set the directory for the named programs.
local named_program_root = shm.root .. "/" .. "by-name"

-- The currently claimed name (think false = nil but nil makes strict.lua unhappy).
program_name = false

-- Auditlog state
auditlog_enabled = false
function enable_auditlog ()
   jit.auditlog(shm.path("audit.log"))
   auditlog_enabled = true
end

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

-- Profiling with vmprofile --------------------------------

vmprofile_enabled = true

-- Low-level FFI
ffi.cdef[[
int vmprofile_get_profile_size();
void vmprofile_set_profile(void *counters);
]]

local vmprofile_t = ffi.typeof("uint8_t["..C.vmprofile_get_profile_size().."]")

local vmprofiles = {}
local function getvmprofile (name)
   if vmprofiles[name] == nil then
      vmprofiles[name] = shm.create("vmprofile/"..name..".vmprofile", vmprofile_t)
   end
   return vmprofiles[name]
end

function setvmprofile (name)
   C.vmprofile_set_profile(getvmprofile(name))
end

function clearvmprofiles ()
   jit.vmprofile.stop()
   for name, profile in pairs(vmprofiles) do
      shm.unmap(profile)
      shm.unlink("vmprofile/"..name..".vmprofile")
      vmprofiles[name] = nil
   end
   if vmprofile_enabled then
      jit.vmprofile.start()
   end
end

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
   setvmprofile(app.zone)
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
   setvmprofile("engine")
   return status, result
end

-- Restart dead apps.
function restart_dead_apps ()
   if not use_restart then return end
   local restart_delay = 2 -- seconds
   local actions = {}

   for name, app in pairs(app_table) do
      if app.dead and (now() - app.dead.time) >= restart_delay then
         io.stderr:write(("Restarting %s (died at %f: %s)\n")
                         :format(name, app.dead.time, app.dead.error))
         local info = configuration.apps[name]
         table.insert(actions, {'stop_app', {name}})
         table.insert(actions, {'start_app', {name, info.class, info.arg}})
         for linkspec in pairs(configuration.links) do
            local fa, fl, ta, tl = config.parse_link(linkspec)
            if fa == name then
               table.insert(actions, {'link_output', {fa, fl, linkspec}})
            end
            if ta == name then
               table.insert(actions, {'link_input', {ta, tl, linkspec}})
            end
         end
      end
   end

   -- Restart dead apps if necessary.
   if #actions > 0 then apply_config_actions(actions) end
end

-- Configure the running app network to match new_configuration.
--
-- Successive calls to configure() will migrate from the old to the
-- new app network by making the changes needed.
function configure (new_config)
   local actions = compute_config_actions(configuration, new_config)
   apply_config_actions(actions)
   counter.add(configs)
end


-- Stop all apps by loading an empty configuration.
function stop ()
   configure(config.new())
end

-- Removes the claim on a name, freeing it for other programs.
--
-- This relinquish a claim on a name if one exists. if the name does not
-- exist it will raise an error with an error message.
function unclaim_name(claimed_name)
   local name = assert(claimed_name or program_name, "No claim to name.")
   local name_fq = named_program_root .. "/" .. name
   local piddir = assert(S.readlink(name_fq))
   local backlink = piddir .. "/name"

   -- First unlink the backlink
   assert(S.unlink(backlink))

   -- Remove the actual namedir
   assert(S.unlink(name_fq))

   -- Remove from the name from the configuration
   program_name = false
end

-- Claims a name for a program so it's identified by name by other processes.
--
-- The name given to the function must be unique; if a name has been used before
-- by an active process the function will error displaying an appropriate error
-- message.Successive calls to claim_name with the same name will return with
-- inaction. If the program has already claimed a name and this is called with
-- a different name, it will attempt to claim the new name and then unclaim the
-- old name. If an problem occurs whilst claiming the new name, the old name
-- will remain claimed.
function claim_name(name)
   local namedir_fq = named_program_root .. "/" .. name
   local procpid = S.getpid()
   local piddir = shm.root .. "/" .. procpid
   local backlinkdir = piddir.."/name"

   -- If we're being asked to claim the name we already have, return false.
   if program_name == name then
      return
   end

   -- Verify that the by-name directory exists.
   shm.mkdir("by-name/")

   -- Create the new symlink (name has probably been taken if this fails).
   assert(S.symlink(piddir, namedir_fq), "Name already taken.")

   -- We've successfully secured the new name, so we can unclaim the old now.
   if program_name ~= false then unclaim_name(program_name) end

   -- Save our current name so we know what it is later.
   program_name = name

   -- Create a backlink so to the symlink so we can easily cleanup
   assert(S.symlink(namedir_fq, backlinkdir))
end

-- Enumerates the named programs with their PID
--
-- This returns a table programs with the key being the name of the program
-- and the value being the PID of the program. Each program is checked that
-- it's still alive. Any dead program or program without a name is not listed.
-- If the "pidkey" is true, it will have the PID as the key instead of the name.
function enumerate_named_programs(pidkey)
   local progs = {}
   local dirs = shm.children("/by-name")
   if dirs == nil then return progs end
   for _, program in pairs(dirs) do
      local fq = named_program_root .. "/" .. program
      local piddir = S.readlink(fq)
      local pid = tonumber(lib.basename(piddir))
      if S.kill(pid, 0) then progs[lib.basename(fq)] = pid end
   end
   return progs
end

-- Return the configuration actions needed to migrate from old config to new.
function compute_config_actions (old, new)
   local actions = {}

   -- First determine the links that are going away and remove them.
   for linkspec in pairs(old.links) do
      if not new.links[linkspec] then
         local fa, fl, ta, tl = config.parse_link(linkspec)
         table.insert(actions, {'unlink_output', {fa, fl}})
         table.insert(actions, {'unlink_input', {ta, tl}})
         table.insert(actions, {'free_link', {linkspec}})
      end
   end

   -- Do the same for apps.
   for appname, info in pairs(old.apps) do
      if not new.apps[appname] then
         table.insert(actions, {'stop_app', {appname}})
      end
   end

   -- Start new apps, restart reclassed apps, or reconfigure apps with
   -- changed configuration.
   local fresh_apps = {}
   for appname, info in pairs(new.apps) do
      local class, arg = info.class, info.arg
      if not old.apps[appname] then
         table.insert(actions, {'start_app', {appname, class, arg}})
         fresh_apps[appname] = true
      elseif old.apps[appname].class ~= class then
         table.insert(actions, {'stop_app', {appname}})
         table.insert(actions, {'start_app', {appname, class, arg}})
         fresh_apps[appname] = true
      elseif not lib.equal(old.apps[appname].arg, arg) then
         if class.reconfig then
            table.insert(actions, {'reconfig_app', {appname, class, arg}})
         else
            table.insert(actions, {'stop_app', {appname}})
            table.insert(actions, {'start_app', {appname, class, arg}})
            fresh_apps[appname] = true
         end
      else
         -- Otherwise if nothing changed, then nothing to do; we keep
         -- the app around.
      end
   end

   -- Now rebuild links.
   for linkspec,_ in pairs(new.links) do
      local fa, fl, ta, tl = config.parse_link(linkspec)
      local fresh_link = not old.links[linkspec]
      if fresh_link then table.insert(actions, {'new_link', {linkspec}}) end
      if not new.apps[fa] then error("no such app: " .. fa) end
      if not new.apps[ta] then error("no such app: " .. ta) end
      if fresh_link or fresh_apps[fa] then
         table.insert(actions, {'link_output', {fa, fl, linkspec}})
      end
      if fresh_link or fresh_apps[ta] then
         table.insert(actions, {'link_input', {ta, tl, linkspec}})
      end
   end

   return actions
end

-- Update the active app network by applying the necessary actions.
function apply_config_actions (actions)
   -- Table of functions that execute config actions
   local ops = {}
   -- As an efficiency hack, some apps rely on the fact that we add
   -- links both by name and by index to the "input" and "output"
   -- objects.  Probably they should be changed to just collect their
   -- inputs and outputs in their :link() functions.  Until then, call
   -- this function when removing links from app input/output objects.
   local function remove_link_from_array(array, link)
      for i=1,#array do
         if array[i] == link then
            table.remove(array, i)
            return
         end
      end
   end
   function ops.unlink_output (appname, linkname)
      local app = app_table[appname]
      local link = app.output[linkname]
      app.output[linkname] = nil
      remove_link_from_array(app.output, link)
      if app.link then app:link() end
   end
   function ops.unlink_input (appname, linkname)
      local app = app_table[appname]
      local link = app.input[linkname]
      app.input[linkname] = nil
      remove_link_from_array(app.input, link)
      if app.link then app:link() end
   end
   function ops.free_link (linkspec)
      link.free(link_table[linkspec], linkspec)
      link_table[linkspec] = nil
      configuration.links[linkspec] = nil
   end
   function ops.new_link (linkspec)
      link_table[linkspec] = link.new(linkspec)
      configuration.links[linkspec] = true
   end
   function ops.link_output (appname, linkname, linkspec)
      local app = app_table[appname]
      local link = assert(link_table[linkspec])
      app.output[linkname] = link
      table.insert(app.output, link)
      if app.link then app:link() end
   end
   function ops.link_input (appname, linkname, linkspec)
      local app = app_table[appname]
      local link = assert(link_table[linkspec])
      app.input[linkname] = link
      table.insert(app.input, link)
      if app.link then app:link() end
   end
   function ops.stop_app (name)
      local app = app_table[name]
      if app.stop then app:stop() end
      if app.shm then shm.delete_frame(app.shm) end
      app_table[name] = nil
      configuration.apps[name] = nil
   end
   function ops.start_app (name, class, arg)
      local app = class:new(arg)
      if type(app) ~= 'table' then
         error(("bad return value from app '%s' start() method: %s"):format(
                  name, tostring(app)))
      end
      local zone = app.zone or getfenv(class.new)._NAME or name
      app.appname = name
      app.output = {}
      app.input = {}
      app_table[name] = app
      app.zone = zone
      if app.shm then
         app.shm.dtime = {counter, C.get_unix_time()}
         app.shm = shm.create_frame("apps/"..name, app.shm)
      end
      configuration.apps[name] = { class = class, arg = arg }
   end
   function ops.reconfig_app (name, class, arg)
      local app = app_table[name]
      app:reconfig(arg)
      configuration.apps[name].arg = arg
   end

   -- Dispatch actions.
   for _, action in ipairs(actions) do
      local name, args = unpack(action)
      if log then io.write("engine: ", name, " ", args[1], "\n") end
      assert(ops[name], name)(unpack(args))
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
      for _,succ in ipairs(successors[node]) do maybe_visit(succ) end
      table.insert(post_order, node)
   end
   function maybe_visit(node)
      if not visited[node] then visit(node) end
   end
   for _,node in ipairs(entries) do maybe_visit(node) end
   for _,node in ipairs(nodes) do maybe_visit(node) end
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
   local pull_links, inputs, successors = {}, {}, {}
   local linknames, appnames = {}, {}
   local function cmp_apps(a, b) return appnames[a] < appnames[b] end
   local function cmp_links(a, b) return linknames[a] < linknames[b] end
   for appname,app in pairs(app_table) do
      appnames[app] = appname
      if app.pull then
         table.insert(breathe_pull_order, app)
         for _,link in pairs(app.output) do
            pull_links[link] = true;
            successors[link] = {}
         end
      end
      for linkname,link in pairs(app.input) do
         linknames[link] = appname..'.'..linkname
         inputs[link] = app
      end
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
   local function keys(x)
      local ret = {}
      for k,v in pairs(x) do table.insert(ret, k) end
      return ret
   end
   local nodes, entry_nodes = keys(inputs), keys(pull_links)
   table.sort(breathe_pull_order, cmp_apps)
   table.sort(nodes, cmp_links)
   table.sort(entry_nodes, cmp_links)
   for link,succs in pairs(successors) do
      successors[link] = keys(succs)
      table.sort(successors[link], cmp_links)
   end
   local link_order = tsort(nodes, entry_nodes, successors)
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

   -- Enable auditlog
   if not auditlog_enabled then
      enable_auditlog()
   end

   -- Setup vmprofile
   setvmprofile("engine")

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

   -- Switch to catch-all profile
   setvmprofile("program")
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
      lastfrees = tonumber(counter.read(frees))
      lastfreebytes = tonumber(counter.read(freebytes))
      lastfreebits = tonumber(counter.read(freebits))
   end
end

function breathe ()
   running = true
   monotonic_now = C.get_monotonic_time()
   -- Restart: restart dead apps
   restart_dead_apps()
   -- Inhale: pull work into the app network
   local i = 1
   ::PULL_LOOP::
   do
      if i > #breathe_pull_order then goto PULL_EXIT end
      local app = breathe_pull_order[i]
      if app.pull and not app.dead then
         with_restart(app, app.pull)
      end
      i = i+1
      goto PULL_LOOP
   end
   ::PULL_EXIT::
   -- Exhale: push work out through the app network
   i = 1
   ::PUSH_LOOP::
   do
      if i > #breathe_push_order then goto PUSH_EXIT end
      local app = breathe_push_order[i]
      if app.push and not app.dead then
         with_restart(app, app.push)
      end
      i = i+1
      goto PUSH_LOOP
   end
   ::PUSH_EXIT::
   counter.add(breaths)
   -- Commit counters and rebalance freelists at a reasonable frequency
   if counter.read(breaths) % 100 == 0 then
      counter.commit()
      packet.rebalance_freelists()
   end
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
   assert(tostring(orig_link) == tostring(link_table['app1.x -> app2.x']))
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

   -- Check engine stop
   assert(not lib.equal(app_table, {}))
   engine.stop()
   assert(lib.equal(app_table, {}))

   -- Check one can't unclaim a name if no name is claimed.
   assert(not pcall(unclaim_name))
   
   -- Test claiming and enumerating app names
   local basename = "testapp"
   local progname = basename.."1"
   claim_name(progname)
   
   -- Check if it can be enumerated.
   local progs = assert(enumerate_named_programs())
   assert(progs[progname])

   -- Ensure changing the name succeeds
   local newname = basename.."2"
   claim_name(newname)
   local progs = assert(enumerate_named_programs())
   assert(progs[progname] == nil)
   assert(progs[newname])

   -- Ensure unclaiming the name occurs
   unclaim_name()
   local progs = enumerate_named_programs()
   assert(progs[newname] == nil)
   assert(not program_name)
   
end
