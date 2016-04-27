#!../../snabb snsh
local intel = require("apps.intel1g.intel1g")
local pci0 = os.getenv("SNABB_PCI_INTEL1G0")
local nic = intel.Intel1g:new({pciaddr = pci0})

for i,v in pairs(nic:stats()) do
  assert(v == 0, i .. " should be 0")
end
os.exit(0)
