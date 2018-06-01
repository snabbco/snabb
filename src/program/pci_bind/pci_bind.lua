-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local lib = require("core.lib")
local pci = require("lib.hardware.pci")
local S = require("syscall")

local usage = require("program.pci_bind.README_inc")

local long_opts = {
   all = "a",
   bind = "b",
   info = "i",
   help = "h",
   remove = "r",
   unbind = "u"
}

local function verify_and_normalize_pci_path(pci_addr)
   local p = pci.path(pci_addr)
   local msg = "No such device: %s, checked %s. \n\z
      If it was removed, restore with -a"
   if not S.stat(p) then
      print(msg:format(pci_addr, p))
      main.exit(1)
   end
   return p
end

local function write_to_file(filename, content)
   if not lib.writefile(filename, content) then
      print(("Writing to %s failed, quitting"):format(filename))
      main.exit(1)
   end
end

local function print_info(pci_path, pci_addr)
   local eth = lib.firstfile(pci_path .. '/net')
   if not eth then
      print(("Unable to find interface name for %s, quitting."):format(pci_addr))
      print(("If it should have an interface name, run pci_bind -r %s, \n\z
         then pci_bind -a. \z
         Warning: -a rescans all interfaces, not just one."):format(pci_addr))
      main.exit(1) 
   else
      print(("%s is known as %s"):format(pci_addr, eth))
   end
end

function run(args)
   local handlers = {}
   local opts = {}
   local pci_addr
   local pci_path
   function handlers.h (arg) print(usage) main.exit(0) end
   function handlers.u (arg) opts.unbind_driv = true pci_addr = arg end
   function handlers.b (arg) opts.bind_driv = true pci_addr = arg end
   function handlers.i (arg) opts.info = true pci_addr = arg end
   function handlers.r (arg) opts.remove = true pci_addr = arg end
   function handlers.a (arg) opts.rescan_all = true end
   args = lib.dogetopt(args, handlers, "hab:i:r:u:", long_opts)
   if #args > 0 then print(usage) main.exit(1) end
   if pci_addr then
      pci_path = verify_and_normalize_pci_path(pci_addr)
   end
   if opts.info then print_info(pci_path, pci_addr) end
   if opts.bind_driv then
      write_to_file(pci_path .. '/driver/bind', pci.qualified(pci_addr))
      print(("Bound %s back to the kernel."):format(pci_addr))
      print_info(pci_path, pci_addr)
   end
   if opts.unbind_driv then
      write_to_file(pci_path .. '/driver/unbind', pci.qualified(pci_addr))
      print(("Unbound %s, ready for Snabb."):format(pci_addr))
   end
   if opts.remove then
      write_to_file(pci_path .. '/remove', "1")
      local msg = "Successfully removed %s. \z
         Note that this does not let Snabb use it. \n\z
         To restore kernel management, use pci_bind -a. \n\z
         To ready a card for Snabb, use pci_bind -u <PCI address>. \n\z
         Example: pci_bind -u ixgbe 00:02.0"
      print(msg:format(pci_addr))
   end
   if opts.rescan_all then
     write_to_file('/sys/bus/pci/rescan', "1")
     print("Rescanned all PCI devices. Run ifconfig to list kernel-managed devices.")
   end
end
