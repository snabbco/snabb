module(..., package.seeall)

-- common definitions for property-based tests for snabb config

local S = require("syscall")

function make_handle_prop_args(name, duration, pidbox)
  local handler = function(prop_args)
     if #prop_args ~= 1 then
        print("Usage: snabb quickcheck prop_sameval PCI_ADDR")
        os.exit(1)
     end
  
     -- TODO: validate the address
     local pci_addr = prop_args[1]
  
     local pid = S.fork()
     if pid == 0 then
        local cmdline = {"snabb", "lwaftr", "run", "-D", tostring(duration),
            "--conf", "program/lwaftr/tests/data/icmp_on_fail.conf",
            "--reconfigurable", "--on-a-stick", pci_addr}
        -- FIXME: preserve the environment
        S.execve(("/proc/%d/exe"):format(S.getpid()), cmdline, {})
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
