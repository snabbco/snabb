module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local lib = require("core.lib")

require("lib.hardware.pci_h")

--- ### Hardware device information

devices = {}

--- Array of all supported hardware devices.
---
--- Each entry is a "device info" table with these attributes:
---
--- * `pciaddress` e.g. `"0000:83:00.1"`
--- * `vendor` id hex string e.g. `"0x8086"` for Intel.
--- * `device` id hex string e.g. `"0x10fb"` for 82599 chip.
--- * `interface` name of Linux interface using this device e.g. `"eth0"`.
--- * `status` string Linux operational status, or `nil` if not known.
--- * `driver` Lua module that supports this hardware e.g. `"intel10g"`.
--- * `usable` device was suitable to use when scanned? `yes` or `no`

--- Initialize (or re-initialize) the `devices` table.
function scan_devices ()
   for _,device in ipairs(lib.files_in_directory("/sys/bus/pci/devices")) do
      local info = device_info(device)
      if info.driver then table.insert(devices, info) end
   end
end

function device_info (pciaddress)
   local info = {}
   local p = path(pciaddress)
   info.pciaddress = pciaddress
   info.vendor = lib.firstline(p.."/vendor")
   info.device = lib.firstline(p.."/device")
   info.driver = which_driver(info.vendor, info.device)
   if info.driver then
      info.interface = lib.firstfile(p.."/net")
      if info.interface then
         info.status = lib.firstline(p.."/net/"..info.interface.."/operstate")
      end
   end
   info.usable = lib.yesno(is_usable(info))
   return info
end

--- Return the path to the sysfs directory for `pcidev`.
function path(pcidev) return "/sys/bus/pci/devices/"..pcidev end

-- Return the name of the Lua module that implements support for this device.
function which_driver (vendor, device)
   if vendor == '0x8086' then
      if device == '0x10fb' then return 'apps.intel.intel10g' end -- Intel 82599
      if device == '0x10d3' then return 'apps.intel.intel' end    -- Intel 82574L
      if device == '0x105e' then return 'apps.intel.intel' end    -- Intel 82571
   end
end

--- ### Device manipulation.

--- Return true if `device` is safely available for use, or false if
--- the operating systems to be using it.
function is_usable (info)
   return info.driver and (info.interface == nil or info.status == 'down')
end

--- Force Linux to release the device with `pciaddress`.
--- The corresponding network interface (e.g. `eth0`) will disappear.
function unbind_device_from_linux (pciaddress)
    local p = path(pciaddress).."/driver/unbind"
    if lib.can_write(p) then
        lib.writefile(path(pciaddress).."/driver/unbind", pciaddress)
    end
end

-- Memory map PCI device configuration space.
-- Return two values:
--   Pointer for memory-mapped access.
--   File descriptor for the open sysfs resource file.
function map_pci_memory (device, n)
   local filepath = path(device).."/resource"..n
   local fd = C.open_pci_resource(filepath)
   assert(fd >= 0)
   local addr = C.map_pci_resource(fd)
   assert( addr ~= 0 )
   return addr, fd
end

-- Close a file descriptor opened by map_pci_memory().
-- XXX should also unmap the memory.
function close_pci_resource (fd, base)
   C.close_pci_resource(fd, base)
end

--- Enable or disable PCI bus mastering. DMA only works when bus
--- mastering is enabled.
function set_bus_master (device, enable)
   local fd = C.open_pcie_config(path(device).."/config")
   local value = ffi.new("uint16_t[1]")
   assert(C.pread(fd, value, 2, 0x4) == 2)
   if enable then
      value[0] = bit.bor(value[0], lib.bits({Master=2}))
   else
      value[0] = bit.band(value[0], bit.bnot(lib.bits({Master=2})))
   end
   assert(C.pwrite(fd, value, 2, 0x4) == 2)
   C.close(fd)
end

--- ### Selftest
---
--- PCI selftest scans for available devices and performs our driver's
--- self-test on each of them.

function selftest ()
   print("selftest: pci")
   scan_devices()
   print_device_summary()
end

function print_device_summary ()
   local attrs = {"pciaddress", "vendor", "device", "interface", "status",
                  "driver", "usable"}
   local fmt = "%-13s %-7s %-7s %-10s %-9s %-11s %s"
   print(fmt:format(unpack(attrs)))
   for _,info in ipairs(devices) do
      local values = {}
      for _,attr in ipairs(attrs) do
         table.insert(values, info[attr] or "-")
      end
      print(fmt:format(unpack(values)))
   end
end

function open_usable_devices (options)
   local drivers = {}
   for _,device in ipairs(devices) do
      if #drivers == 0 then
         if device.usable == 'yes' then
            if device.interface ~= nil then
               print("Unbinding device from linux: "..device.pciaddress)
               unbind_device_from_linux(device.pciaddress)
            end
            print("Opening device "..device.pciaddress)
            local driver = open_device(device.pciaddress, device.driver)
            driver:open_for_loopback_test()
            table.insert(drivers, driver)
         end
      end
   end
   local options = {devices=drivers,
                    program=port.Port.loopback_test,
                    report=true}
   port.selftest(options)
end
