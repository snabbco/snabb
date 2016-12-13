#!/usr/bin/env luajit
module(..., package.seeall)

-- Make sure running a snabb config get twice results in the
-- same values getting returned

local genyang = require("program.lwaftr.tests.propbased.genyang")
local common  = require("program.lwaftr.tests.propbased.common")
local run_pid = {}
local current_cmd

function property()
   local xpath = genyang.generate_config_xpath()
   local get = genyang.generate_get(run_pid[1], xpath)
   current_cmd = get

   local results  = (genyang.run_yang(get))

   if common.check_crashed(results) then
      return false
   end

   -- queried data doesn't exist most likely (or some other non-fatal error)
   if results:match("short read") then
      -- just continue because it's not worth trying to set this property
      return
   end

   local set = genyang.generate_set(run_pid[1], xpath, results)
   results_set = genyang.run_yang(set)
   current_cmd = set

   if common.check_crashed(results_set) then
      return false
   end

   local results2 = (genyang.run_yang(get))
   current_cmd = get

   if common.check_crashed(results2) then
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
   common.make_handle_prop_args("prop_sameval", 40, run_pid)

cleanup = common.make_cleanup(run_pid)
