module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local lib = require("core.lib")
local pci = require ("lib.hardware.pci")

require("lib.hardware.vfio_h")

-- Is VFIO initialized yet?
initialized = false

-- This path is used if the "SNABB_VFIO_DRIVER" environment variable is not defined
VFIO_DEFAULT_DRIVER_PATH = "/sys/bus/pci/drivers/vfio-pci"

-- Array of mappings that were requested before vfio was initialized.
-- 
-- These must then be mapped at initialization time.
pending_mappings = {}

-- Map memory to the IOMMU so that it can be used for DMA.
function map_memory_to_iommu (pointer, size)
   local addr = ffi.cast("uint64_t", pointer)
   if initialized then
      -- Create a 1:1 address mapping for this memory.
      assert(C.mmap_memory(pointer, size, addr, true, true) ~= 0ULL)
   else
      table.insert(pending_mappings, {pointer = pointer, size = size})
   end
   return addr
end

--- ### Hardware device information

--- pciaddress -> info dictionary
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

--- gets some data from /sys/... files
--  stores it in the vfio.devices table
function device_info (pciaddress)
   local info = {}
   local p = pci.path(pciaddress)
   info.pciaddress = pciaddress
   info.vendor = lib.firstline(p.."/vendor")
   info.device = lib.firstline(p.."/device")
   info.iommu_group = device_group(pciaddress)
   info.interface = lib.firstfile(p.."/net")
   info.driver = pci.which_driver(info.vendor, info.device)
   if info.interface then
      info.status = lib.firstline(p.."/net/"..info.interface.."/operstate")
   end
   info.usable = lib.yesno(pci.is_usable(info))
   devices[pciaddress] = info
   return info
end

-- Returns the iommu group of a device
function device_group(pciaddress)
    return lib.basename(lib.readlink(pci.path(pciaddress)..'/iommu_group'))
end

-- Return all the devices that belong to the same group
function group_devices(group)
    if not group then return {} end
    return lib.files_in_directory('/sys/kernel/iommu_groups/'..group..'/devices/')
end

--- ### Device manipulation.

function get_driver_path ()
   return os.getenv("SNABB_VFIO_DRIVER") or VFIO_DEFAULT_DRIVER_PATH
end

--- add a device to the vfio-pci driver
function bind_device_to_vfio (pciaddress)
   lib.writefile(get_driver_path() .. "/bind", pciaddress)
end

function setup_vfio(pciaddress, do_group)
    if do_group then
        for _,f in ipairs(group_devices(device_group(pciaddress))) do
            local addr = lib.basename(f)
            print ('addr:', addr)
            pci.unbind_device_from_linux(addr)
            bind_device_to_vfio(addr)
        end
    else
        pci.unbind_device_from_linux(pciaddress)
        bind_device_to_vfio(pciaddress)
    end
    if not initialized then
       for _, m in ipairs(pending_mappings) do
          mmap_memory_to_iommu(m.pointer, m.size)
       end
       pending_mappings = {}
       initialized = true
    end
end

function open_device_group(group)
    if not group then return nil end
    local groupfd = C.add_group_to_container(group)
    for _, addr in ipairs(group_devices(group)) do
        devices[addr].groupfd = groupfd
    end
    return groupfd
end

function get_vfio_fd(pciaddress)
    local dev = devices[pciaddress]
    assert(dev, "no such device")

    if not dev.vfio_fd then
        if not dev.groupfd then
            open_device_group(tonumber(dev.iommu_group))
        end
        assert (dev.groupfd and dev.groupfd>=0, "can't open iommu_group "..dev.iommu_group)
        dev.vfio_fd = C.open_device_from_vfio_group(dev.groupfd, pciaddress)
    end
    assert (dev.vfio_fd and dev.vfio_fd>=0, "can't open device from iommu group")
    return dev.vfio_fd
end

--- Return a pointer for MMIO access to `device` resource `n`.
--- Device configuration registers can be accessed this way.
function map_pci_memory (device, n)
    local vfio_fd = get_vfio_fd(device)
    local addr = C.mmap_region(vfio_fd, n)
    assert( addr ~= 0 )
    return addr
end

--- Enable or disable PCI bus mastering. DMA only works when bus
--- mastering is enabled.
function set_bus_master (device, enable)
    local vfio_fd = get_vfio_fd(device)
    local value = ffi.new("uint16_t[1]")
    assert(C.pread_config(vfio_fd, value, 2, 0x4) == 2)
    if enable then
        value[0] = bit.bor(value[0], lib.bits({Master=2}))
    else
        value[0] = bit.band(value[0], bit.bnot(lib.bits({Master=2})))
    end
    assert(C.pwrite_config(vfio_fd, value, 2, 0x4) == 2)
end

--- ### Open a device
---
--- Load a device driver for a devie. A fresh copy of the device
--- driver's Lua module is loaded for each device and the module is
--- told at load-time the PCI address of the device it is controlling.
--- This makes the driver source code short because it can assume that
--- it's always talking to the same device.
---
--- This is achieved with our own require()-like function that loads a
--- fresh copy and passes the PCI address as an argument.

open_devices = {}

-- Load a new instance of the 'driver' module for 'pciaddress'.
function open_device(pciaddress, driver)
   return require(driver).new(pciaddress)
end

--- ### Selftest
---
--- PCI selftest scans for available devices and performs our driver's
--- self-test on each of them.

function selftest ()
   print("selftest: vfio")
   print_device_summary()
end

function print_device_summary ()
   local attrs = {"pciaddress", "vendor", "device", "interface", "status",
                  "driver", "usable"}
   local fmt = "%-13s %-7s %-7s %-10s %-9s %-11s %s"
   print(fmt:format(unpack(attrs)))
   for _,info in pairs(devices) do
      local values = {}
      for _,attr in ipairs(attrs) do
         table.insert(values, info[attr] or "-")
      end
      print(fmt:format(unpack(values)))
   end
end

