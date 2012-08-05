-- test.lua -- Test suite for the Snabb Switch.
-- Copright 2012 Snabb GmbH

-- This program expects to run in a tmp directory that has been
-- initialized with bin/tracemaker and to have bin/ in the path.

local tests  = 0
local failed = 0
function check (name, condition)
   tests = tests + 1
   if condition == false then
      print("Test failed: "..name)
      failed = failed + 1
   end
end   

-- Check that known-bad traces do indeed fail the expected tests.
function test_failure_cases ()
   check( "pass",    shell("tester passall.cap") )
   check( "loop",    shell("tester failloop.cap    | grep -q loop.failed") )
   check( "drop",    shell("tester faildrop.cap    | grep -q drop.failed") )
   check( "forward", shell("tester failforward.cap | grep -q forward.failed") )
   check( "flood",   shell("tester failflood.cap   | grep -q flood.failed") )
end

function shell(fmt, ...)
   local result = os.execute("bash -c '"..fmt:format(...).." &>/dev/null'")
   return (result == 0), result
end

function main ()
   test_failure_cases()
   if failed == 0 then
      print("Success! " .. tests .. " test(s) passed.")
   else
      print("Failed! "..failed.."/"..tests.." test(s) failed.")
   end
end

main()

