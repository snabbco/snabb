
--- ### Select bus driver between classic PCI and VFIO
module(...,package.seeall)

local ffi = require('ffi')
local C = ffi.C

local lib = require('core.lib')
local pci = require('lib.hardware.pci')
local vfio = require('lib.hardware.vfio')
local memory = require("core.memory")



devices = {}
map_devices = {}

function scan_devices ()
    for _,device in ipairs(lib.files_in_directory(pci.get_pci_device_path())) do
        local info = device_info(device)
        if info.driver and not map_devices[device] then
            table.insert(devices, info)
            map_devices[device] = info
        end
    end
end

function host_has_vfio()
    local files = lib.files_in_directory(vfio.get_iommu_groups_path())
    return files and #files > 0
end


function device_in_vfio(devicepath)
    local iommu_group = lib.basename(lib.readlink(devicepath..'/iommu_group'))
    if not iommu_group then return false end
    local drivername = lib.basename(lib.readlink(devicepath..'/driver'))
    return drivername == 'vfio-pci'
end


function device_info(pciaddress)
    if map_devices[pciaddress] then
        return map_devices[pciaddress]
    end

    local pcidevpath = pci.path(pciaddress)
    if device_in_vfio(pcidevpath) then
        info  = vfio.device_info(pciaddress)
        info.bus = 'vfio'
        info.device_info = vfio.device_info
        info.map_pci_memory = vfio.map_pci_memory
        info.set_bus_master = vfio.set_bus_master
        info.dma_alloc = memory.dma_alloc
    else
        info = pci.device_info(pciaddress)
        info.bus = 'pci'
        info.device_info = pci.device_info
        info.map_pci_memory = pci.map_pci_memory
        info.set_bus_master = pci.set_bus_master
        info.dma_alloc = memory.dma_alloc
    end
    return info
end

function map_pci_memory(pciaddress, n)
    return map_devices[pciaddress].map_pci_memory(pciaddress, n)
end

function set_bus_master(pciaddress, enable)
    return map_devices[pciaddress].set_bus_master(pciaddress, enable)
end

function selftest ()
    print("selftest: bus")
    scan_devices()
    for _,info in ipairs(devices) do
        print (string.format("device %s: %s", info.pciaddress, info.bus))
    end
end

if host_has_vfio() then
    memory.ram_to_io_addr = vfio.map_memory_to_iommu
else
    memory.set_use_physical_memory()
end
memory.set_default_allocator(true)
