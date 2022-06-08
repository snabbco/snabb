module(..., package.seeall)

local S = require("syscall")
local shm = require("core.shm")
local timer = require("core.timer")
local engine = require("core.app")
local config = require("core.config")
local counter = require("core.counter")

CSVStatsTimer = {}

local function open_link_counters(pid)
   local counters = {}
   for _, linkspec in ipairs(shm.children("/"..pid.."/links")) do
      local fa, fl, ta, tl = config.parse_link(linkspec)
      local link = shm.open_frame("/"..pid.."/links/"..linkspec)
      if not counters[fa] then counters[fa] = {input={},output={}} end
      if not counters[ta] then counters[ta] = {input={},output={}} end
      counters[fa].output[fl] = link
      counters[ta].input[tl] = link
   end
   return counters
end

-- A timer that monitors packet rate and bit rate on a set of links,
-- printing the data out to a CSV file.
--
-- Standard mode example (default):
--
-- Time (s),decap MPPS,decap Gbps,encap MPPS,encap Gbps
-- 0.999197,3.362784,13.720160,3.362886,15.872824
-- 1.999181,3.407569,13.902880,3.407569,16.083724
--
-- Hydra mode example:
--
-- benchmark,id,score,unit
-- decap_mpps,1,3.362784,mpps
-- decap_gbps,1,13.720160,gbps
-- encap_mpps,1,3.362886,mpps
-- encap_gbps,1,15.872824,gbps
-- decap_mpps,2,3.407569,mpps
-- decap_gbps,2,13.902880,gbps
-- encap_mpps,2,3.407569,mpps
-- encap_gbps,2,16.083724,gbps
--
function CSVStatsTimer:new(filename, hydra_mode, pid)
   local file = filename and io.open(filename, "w") or io.stdout
   local o = { hydra_mode=hydra_mode, link_data={}, file=file, period=1,
      header = hydra_mode and "benchmark,id,score,unit" or "Time (s)"}
   o.ready = false
   o.deferred_apps = {}
   o.pid = pid or S.getpid()
   return setmetatable(o, {__index = CSVStatsTimer})
end

function CSVStatsTimer:resolve_app(deferred)
   local id, links, link_names = unpack(assert(deferred))
   self.links_by_app = open_link_counters(self.pid)
   local app = self.links_by_app[id]
   if not app then return false end
   local resolved_links = {}
   for _,name in ipairs(links) do
      local link = app.input[name] or app.output[name]
      -- If we didn't find these links, allow a link name of "rx" to be
      -- equivalent to an input named "input", and likewise for "tx" and
      -- outputs named "output".  This papers over intel_mp versus
      -- intel10g differences, and is especially useful when accessing
      -- remote counters where you don't know what driver the data plane
      -- using.
      if not link then
         if name == 'rx' then link = app.input.input end
         if name == 'tx' then link = app.output.output end
      end
      if not link then return false end
      table.insert(resolved_links, {name, link})
   end
   for _, resolved_link in ipairs(resolved_links) do
      local name, link = unpack(resolved_link)
      local link_name = link_names[name] or name
      local data = {
         link_name = link_name,
         txpackets = link.txpackets,
         txbytes = link.txbytes,
         avg_mpps = nil,
         avg_gbps = nil
      }
      if not self.hydra_mode then
         local h = (',%s MPPS,%s Gbps'):format(link_name, link_name)
         self.header = self.header..h
      end
      table.insert(self.link_data, data)
   end
   return true
end

-- Add links from an app whose identifier is ID to the CSV timer.  If
-- present, LINKS is an array of strings identifying a subset of links
-- to monitor.  The optional LINK_NAMES table maps link names to
-- human-readable names, for the column headers.
function CSVStatsTimer:add_app(id, links, link_names)
   -- Because we are usually measuring counters from another process and
   -- that process is probably spinning up as we are installing the
   -- counter, we defer the resolve operation and try to resolve it from
   -- inside the timer.
   table.insert(self.deferred_apps, {id, links, link_names})
end

function CSVStatsTimer:set_period(period) self.period = period end

-- Activate the timer with a period of PERIOD seconds.
function CSVStatsTimer:start()
   local function tick() return self:tick() end
   self.tick_timer = timer.new('csv_stats', tick, self.period*1e9, 'repeating')
   tick()
   timer.activate(self.tick_timer)
end

function CSVStatsTimer:stop()
   self:tick() -- ?
   timer.cancel(self.tick_timer)
   self:summary()
end

function CSVStatsTimer:is_ready()
   if self.ready then return true end
   for i,data in ipairs(self.deferred_apps) do
      if not data then
         -- pass
      elseif self:resolve_app(data) then
         self.deferred_apps[i] = false
      else
         return false
      end
   end
   -- print header
   self.file:write(self.header..'\n')
   self.file:flush()
   self.start = engine.now()
   self.prev_elapsed = 0
   for _,data in ipairs(self.link_data) do
      data.prev_txpackets = counter.read(data.txpackets)
      data.prev_txbytes = counter.read(data.txbytes)
   end
   self.ready = true
   -- Return false for the last time, so that our first reading is
   -- legit.
   return false
end

function CSVStatsTimer:tick()
   if not self:is_ready() then return end
   local elapsed = engine.now() - self.start
   local dt = elapsed - self.prev_elapsed
   self.prev_elapsed = elapsed
   if not self.hydra_mode then
      self.file:write(('%f'):format(elapsed))
   end
   for _,data in ipairs(self.link_data) do
      local txpackets = counter.read(data.txpackets)
      local txbytes = counter.read(data.txbytes)
      local diff_txpackets = tonumber(txpackets - data.prev_txpackets) / dt / 1e6
      local diff_txbytes = tonumber(txbytes - data.prev_txbytes) * 8 / dt / 1e9
      data.prev_txpackets = txpackets
      data.prev_txbytes = txbytes
      data.avg_mpps = (data.avg_mpps and (data.avg_mpps + diff_txpackets) / 2) or diff_txpackets
      data.avg_gbps = (data.avg_gbps and (data.avg_gbps + diff_txbytes) / 2) or diff_txbytes
      if self.hydra_mode then
         -- Hydra reports seem to prefer integers for the X (time) axis.
         self.file:write(('%s_mpps,%.f,%f,mpps\n'):format(
            data.link_name,elapsed,diff_txpackets))
         self.file:write(('%s_gbps,%.f,%f,gbps\n'):format(
            data.link_name,elapsed,diff_txbytes))
      else
         self.file:write((',%f'):format(diff_txpackets))
         self.file:write((',%f'):format(diff_txbytes))
      end
   end
   if not self.hydra_mode then
      self.file:write('\n')
   end
   self.file:flush()
end

function CSVStatsTimer:summary()
   if not self.hydra_mode then
      for _,data in ipairs(self.link_data) do
         if data.avg_mpps then
            self.file:write(('%s avg. Mpps: %f\n'):format(data.link_name, data.avg_mpps))
         end
         if data.avg_gbps then
            self.file:write(('%s avg. Gbps: %f\n'):format(data.link_name, data.avg_gbps))
         end
      end
   end
end
