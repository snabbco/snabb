module(...,package.seeall)

local buffer = require("core.buffer")
local packet = require("core.packet")
local lib    = require("core.lib")
local link   = require("core.link")
local config = require("core.config")
require("core.packet_h")

-- The set of all active apps and links in the system.
-- Indexed both by name (in a table) and by number (in an array).
app_table,  app_array  = {}, {}
link_table, link_array = {}, {}

configuration = config.new()

function configure (new_config)
   local actions = compute_config_actions(configuration, new_config)
   apply_config_actions(actions, new_config)
end

-- Return the configuration actions needed to migrate from old config to new.
-- The return value is a table:
--   app_name -> stop | start | keep | restart | reconfig
function compute_config_actions (old, new)
   local actions = {}
   for appname, info in pairs(new.apps) do
      local class, config = unpack(info)
      local action = nil
      if not old.apps[appname]                  then action = 'start'
      elseif old.apps[appname].class ~= class   then action = 'restart'
      elseif old.apps[appname].config ~= config then action = 'reconfig'
      else                                           action = 'keep'  end
      actions[appname] = action
   end
   for appname in pairs(old.apps) do
      if not new.apps[appname] then actions[appname] = 'stop' end
   end
   return actions
end

-- Update the active app network by applying the necessary actions.
function apply_config_actions (actions, conf)
   -- The purpose of this function is to populate these tables:
   local new_app_table,  new_app_array  = {}, {}, {}
   local new_link_table, new_link_array = {}, {}, {}
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
   end
   function ops.start (name)
      local class = conf.apps[name].class
      local arg = conf.apps[name].arg
      local app = class:new(arg)
      app.output = {}
      app.input = {}
      new_app_table[name] = app
      table.insert(new_app_array, app)
      app_name_to_index[name] = #new_app_array
      print("started " .. name)
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
   -- dispatch all actions
   for name, action in pairs(actions) do
      print(name, action)
      ops[action](name)
   end
   -- Setup links: create (or reuse) and renumber.
   for linkspec in pairs(conf.links) do
      local fa, fl, ta, tl = config.parse_link(linkspec)
      print(("%q %q %q %q %q"):format(linkspec, fa, fl, ta, tl))
      assert(new_app_table[fa], "'from' app does not exist for link")
      assert(new_app_table[ta], "'to' app does not exist for link: " .. ta)
      -- Create or reuse a link and assign/update receiving app index
      local link = link_table[linkspec] or link.new()
      print("link", link)
      link.receiving_app = app_name_to_index[ta]
      -- Add link to apps
      new_app_table[fa].output[fl] = link
      new_app_table[ta].input[tl] = link
      -- Remember link
      new_link_table[linkspec] = link
      table.insert(new_link_array, link)
   end
   -- commit changes
   app_table, link_table = new_app_table, new_link_table
   app_array, link_array = new_app_array, new_link_array
end

-- Call this to "run snabb switch".
function main ()
   local deadline = lib.timer(1e6)
   repeat breathe() until deadline()
   print("link report")
   for name, l in pairs(link_table) do
      print(name, lib.comma_value(tostring(tonumber(l.stats.txpackets))) .. " packet(s) transmitted")
   end
end

function breathe ()
   -- Inhale: pull work into the app network
   for _, app in ipairs(app_array) do
      if app.pull then app:pull() end
   end
   -- Exhale: push work out through the app network
   repeat
      local progress = false
      -- For each link that has new data, run the receiving app
      for _, link in ipairs(link_array) do
         if link.has_new_data then
            link.has_new_data = false
            local receiver = active_apps[link.receiving_app]
            if receiver.push then
               receiver:push()
               progress = true
            end
         end
      end
   until not progress  -- Stop after no link had new data
end

function selftest ()
   local c = config.new()
   c.app.vhost_user = {VhostUser, [[{path = "/home/luke/qemu.sock"}]]}
   config.app(c, "vhost_user", VhostUser, [[{path = "/home/luke/qemu.sock"}]])
   config.app(c, "intel",      Intel82599, [[{pciaddr = "0000:01:00.0"}]])
   config.app(c, "vhost_tee",  Tee)
   config.app(c, "intel_tee",  Tee)
   config.app(c, "vhost_dump", PcapWriter, [[{filename = "/tmp/vhost.cap"}]])
   config.app(c, "intel_dump", PcapWriter, [[{filename = "/tmp/intel.cap"}]])
   -- VM->Network path
   config.link(c, "vhost_user.tx -> vhost_tee.input")
   config.link(c, " vhost_tee.dump -> vhost_dump.input")
   config.link(c, " vhost_tee.xmit -> intel.rx")
   -- Network->VM path
   config.link(c, "intel.tx -> intel_tee.input")
   config.link(c, " intel_tee.dump -> intel_dump.input")
   config.link(c, " intel_tee.xmit -> vhost_user.rx")
end

--[[ Have to fix all of this.

function report ()
   print("link report")
   for name, l in pairs(links) do
      print(name, lib.comma_value(tostring(tonumber(l.ring.stats.tx))) .. " packet(s) transmitted")
   end
   for name, app in pairs(apps) do
      if app.report then app:report() end
   end
end

--- # Diagnostics

function graphviz ()
   local viz = 'digraph app {\n'
   for appname,app in pairs(apps) do
      viz = viz..'  '..appname..'\n'
   end
   for _,link in pairs(links) do
      local traffic = lib.comma_value(tonumber(link.ring.stats.tx))
      viz = viz..'  '..link.iapp.." -> "..link.oapp..' [label="'..traffic..'"]\n'
   end
   viz = viz..'}\n'
   return viz
end

--]]

function module_init ()
   -- XXX Find a better place for this.
   require("lib.hardware.bus").scan_devices()
end

module_init()
