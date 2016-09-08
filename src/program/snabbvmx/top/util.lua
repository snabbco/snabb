-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Utility functions called by both top.lua nearby, and by each app command
-- which displays stats to the terminal, both in the "top" output and outside,
-- like the lwAFTR "query" subcommand.

module(..., package.seeall)

local shm = require("core.shm")
local S = require("syscall")

function select_snabb_instance (pid)
   local instances = shm.children("//")
   if pid then
      -- Try to use the given pid.
      for _, instance in ipairs(instances) do
         if instance == pid then return pid end
      end
      print("No such Snabb instance: "..pid)
   elseif #instances == 2 then
      -- Two means one is us, so we pick the other.
      local own_pid = tostring(S.getpid())
      if instances[1] == own_pid then return instances[2]
      else                            return instances[1] end
   elseif #instances == 1 then
      -- One means there's only us, or something is very much wrong. :-)
      print("No Snabb instance found.")
   else
      print("Data from multiple Snabb instances found: select a PID from /var/run/snabb.")
   end
   os.exit(1)
end

function pad_str (s, n)
   local padding = math.max(n - s:len(), 0)
   return ("%s%s"):format(s:sub(1, n), (" "):rep(padding))
end

function print_row (spec, args)
   for i, s in ipairs(args) do
      io.write((" %s"):format(pad_str(s, spec[i])))
   end
   io.write("\n")
end

function float_s (n)
   return ("%.2f"):format(n)
end
