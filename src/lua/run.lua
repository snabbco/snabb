-- run.lua -- Run a switch based on a given configuration file.
-- For testing switch behavior from test input files.
-- 
-- Copyright 2012 Snabb GmbH. See the file LICENSE.

module("run",package.seeall)

-- These important modules can be global.
_G.switch = require "switch"
_G.medium = require "medium"

if #arg < 1 then
   io.stderr:write("Usage: run <config> ...\n")
   os.exit(1)
end

dofile(arg[1])

