module(...,package.seeall)

local app = require("core.app")
local buffer = require("core.buffer")
local timer = require("core.timer")
local basic_apps = require("apps.basic.basic_apps")

local graphviz = false

function run ()
   app.apps.source = app.new(basic_apps.Source:new())
   app.apps.join   = app.new(basic_apps.Join:new())
   app.apps.split  = app.new(basic_apps.Split:new())
   app.apps.sink   = app.new(basic_apps.Sink:new())
   app.connect("source", "out", "join",  "in")
   app.connect("join",   "out", "split", "in")
   app.connect("split",  "out", "sink",  "in")
   app.relink()
   buffer.preallocate(10000)
   timer.init()
   timer.activate(timer.new("report", report, 1e9, 'repeating'))
   while true do
      app.breathe()
      timer.run()
   end
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

