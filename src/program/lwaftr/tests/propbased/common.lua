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
        -- preserve PATH variable because the get-state test relies on
        -- this variable being set to print useful results
        local pth = os.getenv("PATH")
        local env = { ("PATH=%s"):format(pth) }
        S.execve(("/proc/%d/exe"):format(S.getpid()), cmdline, env)
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
