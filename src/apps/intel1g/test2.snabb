#!../../snabb snsh
local intel = require("apps.intel1g.intel1g")
local pci0 = os.getenv("SNABB_PCI_INTEL1G0")
local pci1 = os.getenv("SNABB_PCI_INTEL1G1")
local nic = intel.Intel1g:new({pciaddr = pci0})

nic:unlockSwSwSemaphore()
nic:lockSwSwSemaphore()
if pcall(nic.lockSwSwSemaphore, nic) then
  os.exit(-1)
end
nic:unlockSwSwSemaphore()
nic:lockSwSwSemaphore()
os.exit(0)
