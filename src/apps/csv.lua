module(...,package.seeall)

local app = require("core.app")
local ffi = require("ffi")
local C = ffi.C

-- Frequency at which lines are added to the CSV file.
-- (XXX should be an argument to the app.)
interval = 1.0

CSV = {}

function CSV:new (directory)
   local o = { appfile  = io.open(directory.."/app.csv", "w"),
               linkfile = io.open(directory.."/link.csv", "w") }
   o.appfile:write("time,name,class,cpu,crashes,starttime\n")
   o.appfile:flush()
   o.linkfile:write("time,from_app,from_port,to_app,to_port,txbytes,txpackets,rxbytes,rxpackets,dropbytes,droppackets\n")
   o.linkfile:flush()
   timer.new('CSV',
             function () o:output() end,
             1e9,
             'repeating')
   return setmetatable(o, {__index = CSV})
end

function CSV:pull ()
   local now = engine.now()
   if self.next_report and self.next_report > now then
      return
   end
   self.next_report = (self.next_report or now) + interval
   for name, app in pairs(app.app_table) do
      self.appfile:write(
         string.format("%f,%s,%s,%d,%d,%d\n",
                       tonumber(now), name, app.zone, 0, 0, 0))
      self.appfile:flush()
   end
   for spec, link in pairs(app.link_table) do
      local fa, fl, ta, tl = config.parse_link(spec)
      local s = link.stats
      self.linkfile:write(
         string.format("%f,%s,%s,%s,%s,%d,%d,%d,%d,%d,%d\n",
                       now,fa,fl,ta,tl,
                       s.txbytes, s.txpackets,
                       s.rxbytes, s.rxpackets,
                       0, s.txdrop))
      self.linkfile:flush()
   end
end

