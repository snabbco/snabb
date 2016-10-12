module(..., package.seeall)

local timer = require("core.timer")
local engine = require("core.app")
local counter = require("core.counter")

CSVStatsTimer = {}

-- A timer that monitors packet rate and bit rate on a set of links,
-- printing the data out to a CSV file.
function CSVStatsTimer:new(filename)
   local file = filename and io.open(filename, "w") or io.stdout
   local o = { header='Time (s)', link_data={}, file=file, period=1 }
   return setmetatable(o, {__index = CSVStatsTimer})
end

-- Add links from an app whose identifier is ID to the CSV timer.  If
-- present, LINKS is an array of strings identifying a subset of links
-- to monitor.  The optional LINK_NAMES table maps link names to
-- human-readable names, for the column headers.
function CSVStatsTimer:add_app(id, links, link_names)
   local function add_link_data(name, link)
      local pretty_name = (link_names and link_names[name]) or name
      local h = (',%s MPPS,%s Gbps'):format(pretty_name, pretty_name)
      self.header = self.header..h
      local data = {
         txpackets = link.stats.input_packets,
         txbytes = link.stats.input_bytes,
      }
      table.insert(self.link_data, data)
   end

   local app = assert(engine.app_table[id], "App named "..id.." not found")
   if links then
      for _,name in ipairs(links) do
         local link = app.input[name] or app.output[name]
         assert(link, "Link named "..name.." not found in "..id)
         add_link_data(name, link)
      end
   else
      for name,link in pairs(app.input) do add_link_data(name, link) end
      for name,link in pairs(app.output) do add_link_data(name, link) end
   end
end

function CSVStatsTimer:set_period(period) self.period = period end

-- Activate the timer with a period of PERIOD seconds.
function CSVStatsTimer:activate()
   self.file:write(self.header..'\n')
   self.file:flush()
   self.start = engine.now()
   self.prev_elapsed = 0
   for _,data in ipairs(self.link_data) do
      data.prev_txpackets = counter.read(data.input_packets)
      data.prev_txbytes = counter.read(data.input_bytes)
   end
   local function tick() return self:tick() end
   local t = timer.new('csv_stats', tick, self.period*1e9, 'repeating')
   timer.activate(t)
   return t
end

function CSVStatsTimer:tick()
   local elapsed = engine.now() - self.start
   local dt = elapsed - self.prev_elapsed
   self.prev_elapsed = elapsed
   self.file:write(('%f'):format(elapsed))
   for _,data in ipairs(self.link_data) do
      local txpackets = counter.read(data.input_packets)
      local txbytes = counter.read(data.input_bytes)
      local diff_txpackets = tonumber(txpackets - data.prev_txpackets)
      local diff_txbytes = tonumber(txbytes - data.prev_txbytes)
      data.prev_txpackets = txpackets
      data.prev_txbytes = txbytes
      self.file:write((',%f'):format(diff_txpackets / dt / 1e6))
      self.file:write((',%f'):format(diff_txbytes * 8 / dt / 1e9))
   end
   self.file:write('\n')
   self.file:flush()
end
