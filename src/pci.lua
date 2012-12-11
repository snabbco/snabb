-- pci.lua -- PCI device access via Linux sysfs.
-- Copyright 2012 Snabb GmbH. See the file LICENSE.

module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
local lib = require("lib")

require("clib_h")
require("snabb_h")

-- Return true if 'device' is an Intel 82574 ethernet controller.
function pcidev_is_82574 (device)
   return io.open(path(device,"config"), "ro"):read(4) == "\x86\x80\xd3\x10"
end

local function path(pcidev, file)
   return "/sys/bus/pci/devices/"..pcidev.."/"..file
end

-- Return a pointer for MMIO access to 'device' resource 'n'.
function map_pci_memory (device, n)
   local filepath = path(device,"resource")..n
   local addr = C.map_pci_resource(filepath)
   assert( addr ~= 0 )
   return addr
end

-- Return a file descriptor for accessing PCI configuration space.
function open_config (device)
   return C.open_pcie_config(path(device, "config"))
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
