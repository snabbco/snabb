-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local S = require("syscall")
local lib = require("core.lib")

local usage = require("program.selftest.README_inc")

local long_opts = {
   ["zap-env"] = "z",
   ["pci"] = "p",
   ["pci-intel"] = "i",
   ["pci-solarflare"] = "s",
   ["pcap-file"] = "f"
}

local pci = {}     -- PCI network devices (unspecified type)
local int = {}     -- ... intel
local snf = {}     -- ... solarflare
local pcap = false -- pcap file containing test input

function run (args)
   local opt = {}
   function opt.z ()
      for i, e in ipairs({'SNABB_PCI0', 'SNABB_PCI1',
                          'SNABB_PCI_INTEL0', 'SNABB_PCI_INTEL1',
                          'SNABB_PCI_SOLARFLARE0', 'SNABB_PCI_SOLARFLARE1',
                          'SNABB_PCAP'}) do
         S.unsetenv(e)
      end
   end
   function opt.p (arg) table.insert(pci, arg) end
   function opt.i (arg) table.insert(int, arg) end
   function opt.s (arg) table.insert(snf, arg) end
   function opt.f (arg) pcap = arg end
   args = lib.dogetopt(args, opt, "zp:i:s:f:", long_opts)
   -- Setup environment variables from the command line
   for i = 1, #pci do S.setenv("SNABB_PCI"..(i-1),            pci[i]) end
   for i = 1, #int do S.setenv("SNABB_PCI_INTEL"..(i-1),      int[i]) end
   for i = 1, #snf do S.setenv("SNABB_PCI_SOLARFLARE"..(i-1), snf[i]) end
   if #args == 2 and args[1] == 'module' then
      require(args[2]).selftest()
   else
      print(usage)
      main.exit(1)
   end
end

