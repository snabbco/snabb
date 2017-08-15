module(..., package.seeall)

-- common definitions for property-based tests for snabb config

local S = require("syscall")
local lib = require("core.lib")
local pci = require("lib.hardware.pci")

function make_handle_prop_args(name, duration, pidbox)
  local handler = function(prop_args)
     if #prop_args ~= 1 then
        print("Usage: snabb lwaftr quickcheck prop_sameval PCI_ADDR")
        os.exit(1)
     end

     local pci_addr = prop_args[1]
     assert(S.stat(pci.path(pci_addr)),
            string.format("Invalid PCI address: %s", pci_addr))

     local pid = S.fork()
     if pid == 0 then
        local cmdline = {"snabb", "lwaftr", "run", "-D", tostring(duration),
            "--conf", "program/lwaftr/tests/data/icmp_on_fail.conf",
            "--on-a-stick", pci_addr}
        lib.execv(("/proc/%d/exe"):format(S.getpid()), cmdline)
     else
        pidbox[1] = pid
        S.sleep(0.1)
     end
  end
  return handler
end

function make_cleanup(pidbox)
   local cleanup = function()
      S.kill(pidbox[1], "TERM")
   end
   return cleanup
end

-- return true if the result from the query indicates a crash/disconnect
function check_crashed(results)
   if results:match("Could not connect to config leader socket on Snabb instance") then
      print("Launching snabb run failed, or we've crashed it!")
      return true
   end
   return false
end
