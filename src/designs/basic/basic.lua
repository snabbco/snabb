module(...,package.seeall)

local app = require("core.app")
local buffer = require("core.buffer")
local timer = require("core.timer")
local basic_apps = require("apps.basic.basic_apps")
local config = require("core.config")

local graphviz = false

function run ()
   local c = config.new()
   config.app(c, "source", basic_apps.Source)
   config.app(c, "join", basic_apps.Join)
   config.app(c, "split", basic_apps.Split)
   config.app(c, "sink", basic_apps.Sink)
   config.link(c, "source.out -> join.in")
   config.link(c, "join.out -> split.in")
   config.link(c, "split.out -> sink.in")
   app.configure(c)
   buffer.preallocate(10000)
   app.main({duration = 1})
--[[
   timer.init()
   timer.activate(timer.new("report", report, 1e9, 'repeating'))
   while true do
      app.breathe()
      timer.run()
   end
--]]
end

function report ()
   app.report()
   if graphviz then
      local f,err = io.open("app-selftest.dot", "w")
      if not f then print("Failed to open app-selftest.dot") end
      f:write(app.graphviz())
      f:close()
   end
end

run()

