-- igbe.lua -- Intel Gigabit Ethernet base driver

local pci = require("lib.hardware.pci")

function configure (conf)
   print("pciaddress: " .. conf.pciaddress)
   pci.unbind_device_from_linux(conf.pciaddress)
   pci.set_bus(self.pciaddress, true)
   initialize()
end

-- [4.6.3 Initialization Sequence]
function initialize ()
   disable_interrupts()
   global_reset_and_general_configuration()
   initialize_phy()
   initialize_statistics_counters()
   -- Skipped, out of scope for this app:
   --   Initialize Receive
   --   Initialize Transmit
   --   Enable Interrupts
end

-- [4.6.4 Interrupts During Initialization]
function disable_interrupts ()
   r[EMIC] = bits({0,1,2,3,4,5,6,7,30,31})
end

-- [4.6.5 Global Reset and General Configuration]
function global_reset_and_general_configuration ()
   r[CTRL] = bits({SLU=6, 
end

-- [4.6.7.1 PHY initialization]
function initialize_phy ()
   -- Expect this to be done in hardware from EEPROM.
end

-- [4.6.8 Initialization of Statistics]
function initialize_statistics_counters ()
   -- No action reqired.
   -- 
   -- Data sheet suggests reading all registers to zero them but it
   -- also specifies that they all have zero as their initial values.
   -- Let's not do unnecessary work.
end

