-- pci.lua -- PCI device access via Linux sysfs.
-- Copyright 2012 Snabb GmbH. See the file LICENSE.

module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
local lib = require("lib")

require("clib_h")
require("snabb_h")

--- ### Hardware device information.

--- Array of all supported hardware devices.
---
--- Each entry is a "device info" table with these attributes:
---     * `pciaddress` e.g. `"0000:83:00.1"`
---     * `vendor` id hex string e.g. `"0x8086"` for Intel.
---     * `device` id hex string e.g. `"0x10fb"` for 82599 chip.
---     * `interface` name of Linux interface using this device e.g. `"eth0"`.
---     * `status` string Linux operational status, or `nil` if not known.
---     * `driver` Lua module that supports this hardware e.g. `"intel10g"`.
---     * `usable` device was suitable to use when scanned? `yes` or `no`
devices = {}

-- Return device information table i.e. value for the devices table.
function scan_devices ()
   for _,device in ipairs(scandir("/sys/bus/pci/devices")) do
      local info = device_info(device)
      if info.driver then table.insert(devices, info) end
   end
end

function scandir (dir)
   local files = {}
   for line in io.popen('ls -1 "'..dir..'" 2>/dev/null'):lines() do
      table.insert(files, line)
   end
   return files
end

-- Return the 
function device_info (pciaddress)
   local info = {}
   local p = path(pciaddress)
   info.pciaddress = pciaddress
   info.vendor = firstline(p.."/vendor")
   info.device = firstline(p.."/device")
   info.interface = firstfile(p.."/net")
   info.driver = which_driver(info.vendor, info.device)
   if info.interface then
      info.status = firstline(p.."/net/"..info.interface.."/operstate")
   end
   info.usable = lib.yesno(is_usable(info))
   return info
end

-- Return the path to the sysfs directory for `pcidev`.
function path(pcidev) return "/sys/bus/pci/devices/"..pcidev end

-- Return the name of the Lua module that implements support for this device.
function which_driver (vendor, device)
   if vendor == '0x8086' and device == '0x10fb' then return 'intel10g' end
   if vendor == '0x8086' and device == '0x10d3' then return 'intel' end
   if vendor == '0x8086' and device == '0x105e' then return 'intel' end
end

function firstline (filename) return lib.readfile(filename, "*l") end

-- Return the name of the first file in `dir`.
function firstfile (dir)
   return lib.readcmd("ls -1 "..dir.." 2>/dev/null", "*l")
end

--- ### Device manipulation.

-- Force Linux to release the device with `pciaddress`.
-- The corresponding network interface (e.g. `eth0`) will disappear.
function unbind_device_from_linux (pciaddress)
   lib.writefile(path(pciaddress).."/driver/unbind", pciaddress)
end

-- Return a pointer for MMIO access to 'device' resource 'n'.
-- Device configuration registers can be accessed this way.
function map_pci_memory (device, n)
   local filepath = path(device).."/resource"..n
   local addr = C.map_pci_resource(filepath)
   assert( addr ~= 0 )
   return addr
end

-- Enable or disable PCI bus mastering.
-- (DMA only works when bus mastering is enabled.)
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
end

-- Return true if `device` is available for use or false if it seems
-- to be used by the operating system.
function is_usable (info)
   return info.driver and (info.interface == nil or info.status == 'down')
end

--- ### Open a device
---
--- Load a fresh copy of the device driver's Lua module for each
--- device. The module will be told at load-time the PCI address of
--- the device it is controlling. This makes the module code short
--- because it can assume that it's always talking to the same device.
---
--- This is achieved with our own require()-like function that loads a
--- fresh copy and passes the PCI address as an argument.

open_devices = {}

-- Load a new instance of the 'driver' module for 'pciaddress'.
-- On success this creates the Lua module 'driver@pciaddress'.
--
-- Example: open_device("intel10g", "0000:83:00.1") creates module
-- "intel10g@0000:83:00.1" which controls that specific device.
function open_device(pciaddress, driver)
   local instance = driver.."@"..pciaddress
   find_loader(driver)(instance, pciaddress)
   open_devices[pciaddress] = package.loaded[instance]
   return package.loaded[instance]
end

-- (This could be a Lua builtin.)
-- Return loader function for `module`.
-- Calling the loader function will run the module's code.
function find_loader (mod)
   for i = 1, #package.loaders do
      status, loader = pcall(package.loaders[i], mod)
      if type(loader) == 'function' then return loader end
   end
end

--- ### Selftest

function selftest ()
   print("selftest: pci")
   print_devices()
   open_usable_devices()
end

--- Print a table summarizing all the available hardware devices.
function print_devices ()
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

function open_usable_devices ()
   for _,device in ipairs(devices) do
      if device.usable == 'yes' then
         if device.interface ~= nil then
            print("Unbinding device from linux: "..device.pciaddress)
            unbind_device_from_linux(device.pciaddress)
         end
         print("Opening device "..device.pciaddress)
         local driver = open_device(device.pciaddress, device.driver)
         print("Testing "..device.pciaddress)
         driver.selftest()
      end
   end
end

function module_init () scan_devices () end

module_init()

