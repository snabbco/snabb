#!/usr/bin/env luajit
module(..., package.seeall)

local genyang = require("program.lwaftr.tests.propbased.genyang")
local common  = require("program.lwaftr.tests.propbased.common")
local run_pid = {}
local current_cmd

function property()
   current_cmd = genyang.generate_any(run_pid[1])
   local results = (genyang.run_yang(current_cmd))
   if common.check_crashed(results) then
      return false
   end
end

function print_extra_information()
   print("The command was:", current_cmd)
end

handle_prop_args =
   common.make_handle_prop_args("prop_nocrash", 20, run_pid)

cleanup = common.make_cleanup(run_pid)
