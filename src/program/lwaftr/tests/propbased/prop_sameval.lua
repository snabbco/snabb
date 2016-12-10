#!/usr/bin/env luajit
module(..., package.seeall)

-- Make sure running a snabb config get twice results in the
-- same values getting returned

local genyang = require("program.lwaftr.tests.propbased.genyang")
local common  = require("program.lwaftr.tests.propbased.common")
local run_pid = {}
local current_cmd

function property()
   current_cmd = genyang.generate_yang(run_pid[1])
   local results  = (genyang.run_yang(current_cmd))
   local results2 = (genyang.run_yang(current_cmd))
   if string.match("Could not connect to config leader socket on Snabb instance",
                   results) or
      string.match("Could not connect to config leader socket on Snabb instance",
                   results2) then
      print("Launching snabb run failed, or we've crashed it!")
      return false
   end

   if results ~= results2 then
      print("Running the same config command twice produced different outputs")
      return false
   end
end

function print_extra_information()
   print("The command was:", current_cmd)
end

handle_prop_args =
   common.make_handle_prop_args("prop_sameval", 20, run_pid)

cleanup = common.make_cleanup(run_pid)
