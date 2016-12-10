module(..., package.seeall)

-- test to make sure repeated get-state commands are ok

local genyang = require("program.lwaftr.tests.propbased.genyang")
local common  = require("program.lwaftr.tests.propbased.common")
local run_pid = {}
local current_cmd

function property()
   current_cmd = genyang.generate_get_state(run_pid[1])
   local results = (genyang.run_yang(current_cmd))
   if string.match("Could not connect to config leader socket on Snabb instance",
                   results) then
      print("Launching snabb run failed, or we've crashed it!")
      return false
   end
end

function print_extra_information()
   print("The command was:", current_cmd)
end

handle_prop_args =
   common.make_handle_prop_args("prop_nocrash_state", 10, run_pid)

cleanup = common.make_cleanup(run_pid)
