-- pci.lua -- PCI device access via Linux sysfs.
-- Copyright 2012 Snabb GmbH. See the file LICENSE.

module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
local lib = require("lib")

require("clib_h")
require("snabb_h")

function suitable_devices ()
   local list = {}
   for _,info in ipairs(devices()) do
      if is_suitable(info) then list[#list + 1] = info end
   end
   return list
end

function is_suitable (info)
   return info.vendor == "0x8086" and info.device == "0x10d3" and
      (info.interface == nil or info.status == 'down')
end

-- Prepare the device with pciaddress for use with the switch.
-- Return true on success.
function prepare_device (pciaddress)
   local device = device_info(pciaddress)
   if device.interface == nil then
         return true
   else
      print("Unbinding PCI device "..pciaddress.." ("..device.interface..") from the operating system driver.")
      local file = io.open(path(pciaddress).."/driver/unbind", "w")
      file:write(pciaddress)
      file.close()
      return is_suitable(device_info(pciaddress))
   end
end

function devices ()
   local info = {}
   for _,device in ipairs(scandir("/sys/bus/pci/devices")) do
      info[#info + 1] = device_info(device)
   end
   return info
end

function device_info (pciaddress)
   local info = {}
   local p = path(pciaddress)
   info.pciaddress = pciaddress
   info.vendor = firstline(p.."/vendor")
   info.device = firstline(p.."/device")
   info.interface = firstfile(p.."/net")
   if info.interface then
      info.status = firstline(p.."/net/"..info.interface.."/operstate")
   end
   return info
end

function firstline(filename)
   local file = io.open(filename, "r")
   if file then
      local line = file:read("*l")
      file.close()
      return line
   end
end

function firstfile(dir)
   for _,file in ipairs(scandir(dir)) do return file end
end

-- Return true if 'device' is an Intel 82574 ethernet controller.
function pcidev_is_82574 (device)
   return io.open(path(device).."/config", "ro"):read(4) == "\x86\x80\xd3\x10"
end

function path(pcidev) return "/sys/bus/pci/devices/"..pcidev end

-- Return a pointer for MMIO access to 'device' resource 'n'.
function map_pci_memory (device, n)
   local filepath = path(device).."/resource"..n
   local addr = C.map_pci_resource(filepath)
   assert( addr ~= 0 )
   return addr
end

-- Return a file descriptor for accessing PCI configuration space.
function open_config (device)
   return C.open_pcie_config(path(device).."/config")
end

-- Close the file descriptor for PCI configuration space access.
function close_config (fd)
   C.close(config)
end

local pci_value = ffi.new("uint16_t[1]")

function read_config (fd, reg)
   assert(C.pread(fd, pci_value, 2, reg) == 2)
   return pci_value[0]
end

function write_config (fd, reg, value)
   pci_value[0] = value
   assert(C.pwrite(fd, pci_value, 2, reg) == 2)
end

function set_bus_master (fd, flag)
   local control = read_config(fd, 0x04)
   if flag then
      control = bit.bor(control, lib.bits({EnableMastering=2}))
   else
      control = bit.band(control, bit.bnot(lib.bits({EnableMastering=2})))
   end
   write_config(fd, 0x04, control)
end

function selftest ()
   print("selftest: pci")
   print("Scanning PCI devices:")
   list_devices()
   local suitable = suitable_devices()
   if #suitable == 0 then
      print("No suitable PCI Ethernet devices found.")
   else
      print("Suitable devices: ")
      for _,device in ipairs(suitable) do
         print("  "..device.pciaddress)
      end
   end
end

function list_devices ()
   print("pciaddr", "", "vendor", "device", "iface", "status")
   for _,d in ipairs(devices()) do
      print(d.pciaddress, d.vendor, d.device, d.interface or "-", d.status or "-")
   end
end

-- Return the names of all files in dir.
-- XXX Consider doing this with luafilesystem (lfs) instead of popen.
function scandir (dir)
   local files = {}
   for filename in io.popen('ls -1 "'..dir..'" 2>/dev/null'):lines() do
      files[#files + 1] = filename
   end
   return files
end

