--- For testing switch behavior from test input files.

module("run",package.seeall)

-- These important modules can be global.
_G.switch = require "switch"
_G.medium = require "medium"
_G.report = require "report"

if #arg < 1 then
   io.stderr:write("Usage: run <config> ...\n")
   os.exit(1)
end

dofile(arg[1])

