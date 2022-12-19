-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
local S = require("syscall")
local shm = require("core.shm")

local lib = require("core.lib")

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
--- * `driver` Lua module that supports this hardware e.g. `"intel_mp"`.
--- * `usable` device was suitable to use when scanned? `yes` or `no`

--- Initialize (or re-initialize) the `devices` table.
function scan_devices ()
   for device in assert(S.util.ls("/sys/bus/pci/devices")) do
      if device ~= '.' and device ~= '..' then
         local info = device_info(device)
         if info.driver then table.insert(devices, info) end
      end
   end
end

function device_info (pciaddress)
   local info = {}
   local p = path(pciaddress)
   assert(S.stat(p), ("No such device: %s"):format(pciaddress))
   info.pciaddress = canonical(pciaddress)
   info.vendor = lib.firstline(p.."/vendor")
   info.device = lib.firstline(p.."/device")
   info.model = which_model(info.vendor, info.device)
   info.driver = which_driver(info.vendor, info.device)
   if info.driver then
      info.rx, info.tx = which_link_names(info.driver)
      info.interface = lib.firstfile(p.."/net")
      if info.interface then
         info.status = lib.firstline(p.."/net/"..info.interface.."/operstate")
      end
   end
   info.usable = lib.yesno(is_usable(info))
   return info
end

--- Return the path to the sysfs directory for `pcidev`.
function path(pcidev) return "/sys/bus/pci/devices/"..qualified(pcidev) end

model = {
   ["82599_SFP"] = 'Intel 82599 SFP',
   ["82574L"]    = 'Intel 82574L',
   ["82571"]     = 'Intel 82571',
   ["82599_T3"]  = 'Intel 82599 T3',
   ["X540"]      = 'Intel X540',
   ["X520"]      = 'Intel X520',
   ["i350"]      = 'Intel 350',
   ["i210"]      = 'Intel 210',
   ["X710"]      = 'Intel X710',
   ["XL710_VF"]  = 'Intel XL710/X710 Virtual Function',
   ["AVF"]       = 'Intel AVF'
}

-- Supported cards indexed by vendor and device id.
local cards = {
   ["0x8086"] =  {
      ["0x10fb"] = {model = model["82599_SFP"], driver = 'apps.intel_mp.intel_mp'},
      ["0x10d3"] = {model = model["82574L"],    driver = 'apps.intel_mp.intel_mp'},
      ["0x105e"] = {model = model["82571"],     driver = 'apps.intel_mp.intel_mp'},
      ["0x151c"] = {model = model["82599_T3"],  driver = 'apps.intel_mp.intel_mp'},
      ["0x1528"] = {model = model["X540"],      driver = 'apps.intel_mp.intel_mp'},
      ["0x154d"] = {model = model["X520"],      driver = 'apps.intel_mp.intel_mp'},
      ["0x1521"] = {model = model["i350"],      driver = 'apps.intel_mp.intel_mp'},
      ["0x1533"] = {model = model["i210"],      driver = 'apps.intel_mp.intel_mp'},
      ["0x157b"] = {model = model["i210"],      driver = 'apps.intel_mp.intel_mp'},
      ["0x154c"] = {model = model["XL710_VF"],  driver = 'apps.intel_avf.intel_avf'},
      ["0x1889"] = {model = model["AVF"],       driver = 'apps.intel_avf.intel_avf'},
      ["0x1572"] = {model = model["X710"],     driver = nil},
   },
   ["0x1924"] =  {
      ["0x0903"] = {model = 'SFN7122F', driver = 'apps.solarflare.solarflare'}
   },
	["0x15b3"] = {
           ["0x1013" ] = {model = 'MT27700', driver = 'apps.mellanox.connectx'},
           ["0x1017" ] = {model = 'MT27800', driver = 'apps.mellanox.connectx'},
           ["0x1019" ] = {model = 'MT28800', driver = 'apps.mellanox.connectx'},
           ["0x101d" ] = {model = 'MT2892',  driver = 'apps.mellanox.connectx'},
	},
}

local link_names = {
   ['apps.solarflare.solarflare'] = { "rx", "tx" },
   ['apps.intel_mp.intel_mp']     = { "input", "output" },
   ['apps.intel_avf.intel_avf']   = { "input", "output" },
   ['apps.mellanox.connectx']     = { "input", "output" },
}

-- Return the name of the Lua module that implements support for this device.
function which_driver (vendor, device)
   local card = cards[vendor] and cards[vendor][device]
   return card and card.driver
end

function which_model (vendor, device)
   local card = cards[vendor] and cards[vendor][device]
   return card and card.model
end

function which_link_names (driver)
   return unpack(assert(link_names[driver]))
end

--- ### Device manipulation.

--- Return true if `device` is safely available for use, or false if
--- the operating systems to be using it.
function is_usable (info)
   return info.driver and (info.interface == nil or info.status == 'down')
end

-- Reset a PCI function.
-- See https://www.kernel.org/doc/Documentation/ABI/testing/sysfs-bus-pci
function reset_device (pciaddress)
   root_check()
   local p = path(pciaddress).."/reset"
   if lib.can_write(p) then
      lib.writefile(p, "1")
   else
      error("Cannot write: "..p)
   end
end

--- Force Linux to release the device with `pciaddress`.
--- The corresponding network interface (e.g. `eth0`) will disappear.
function unbind_device_from_linux (pciaddress)
   root_check()
   local p = path(pciaddress).."/driver/unbind"
   if lib.can_write(p) then
       lib.writefile(path(pciaddress).."/driver/unbind", qualified(pciaddress))
   end
end

-- ### Access PCI devices using Linux sysfs (`/sys`) filesystem
-- sysfs is an interface towards the Linux kernel based on special
-- files that are implemented as callbacks into the kernel. Here are
-- some background links about sysfs:
-- - High-level: <http://en.wikipedia.org/wiki/Sysfs>
-- - Low-level:  <https://www.kernel.org/doc/Documentation/filesystems/sysfs.txt>

-- PCI hardware device registers can be memory-mapped via sysfs for
-- "Memory-Mapped I/O" by device drivers. The trick is to `mmap()` a file
-- such as:
--    /sys/bus/pci/devices/0000:00:04.0/resource0
-- and then read and write that memory to access the device.

-- Memory map PCI device configuration space.
-- Return two values:
--   Pointer for memory-mapped access.
--   File descriptor for the open sysfs resource file.

function open_pci_resource_locked(device,n) return open_pci_resource(device, n, true) end
function open_pci_resource_unlocked(device,n) return open_pci_resource(device, n, false) end

function open_pci_resource (device, n, lock)
   assert(lock == true or lock == false, "Explicit lock status required")
   root_check()
   local filepath = path(device).."/resource"..n
   local f,err  = S.open(filepath, "rdwr, sync")
   assert(f, "failed to open resource " .. filepath .. ": " .. tostring(err))
   if lock then
     assert(f:flock("ex, nb"), "failed to lock " .. filepath)
   end
   return f
end

function map_pci_memory (f)
   local st = assert(f:stat())
   local mem, err = f:mmap(nil, st.size, "read, write", "shared", 0)
   -- mmap() returns EINVAL on Linux >= 4.5 if the device is still
   -- claimed by the kernel driver. We assume that
   -- unbind_device_from_linux() has already been called but it may take
   -- some time for the driver to release the device.
   if not mem and err.INVAL then
      local filepath = S.readlink("/proc/self/fd/"..f:getfd())
      lib.waitfor2("mmap of "..filepath,
                   function ()
                      mem, err = f:mmap(nil, st.size, "read, write", "shared", 0)
                      return mem ~= nil or not err.INVAL
                   end, 10, 1000000)
   end
   assert(mem, err)
   return ffi.cast("uint32_t *", mem)
end

function close_pci_resource (fd, base)
   local st = assert(fd:stat())
   S.munmap(base, st.size)
   fd:close()
end

--- Enable or disable PCI bus mastering. DMA only works when bus
--- mastering is enabled.
function set_bus_master (device, enable)
   root_check()
   local f = assert(S.open(path(device).."/config", "rdwr"))
   local fd = f:getfd()

   local value = ffi.new("uint16_t[1]")
   assert(C.pread(fd, value, 2, 0x4) == 2)
   if enable then
      shm.create('group/dma/pci/'..canonical(device), 'uint64_t')
      value[0] = bit.bor(value[0], lib.bits({Master=2}))
   else
      shm.unlink('group/dma/pci/'..canonical(device))
      value[0] = bit.band(value[0], bit.bnot(lib.bits({Master=2})))
   end
   assert(C.pwrite(fd, value, 2, 0x4) == 2)
   f:close()
end

-- Shutdown DMA to prevent "dangling" requests for PCI devices opened
-- by pid (or other processes in its process group).
--
-- This is an internal API function provided for cleanup during
-- process termination.
function shutdown (pid)
   local dma = shm.children("/"..pid.."/group/dma/pci")
   for _, device in ipairs(dma) do
      -- Only disable bus mastering if we are able to get an exclusive lock on
      -- resource 0 (i.e., no process left using the device.)
      if pcall(open_pci_resource_locked(device, 0)) then
         set_bus_master(device, false)
      end
   end
end

function root_check ()
   lib.root_check("error: must run as root to access PCI devices")
end

-- Return the canonical (abbreviated) representation of the PCI address.
--
-- example: canonical("0000:01:00.0") -> "01:00.0"
function canonical (address)
   return address:gsub("^0000:", "")
end

-- Return the fully-qualified representation of a PCI address.
--
-- example: qualified("01:00.0") -> "0000:01:00.0"
function qualified (address)
   return address:gsub("^%x%x:%x%x[.]%x+$", "0000:%1")
end

--- ### Selftest
---
--- PCI selftest scans for available devices and performs our driver's
--- self-test on each of them.

function selftest ()
   print("selftest: pci")
   assert(qualified("0000:01:00.0") == "0000:01:00.0", "qualified 1")
   assert(qualified(     "01:00.0") == "0000:01:00.0", "qualified 2")
   assert(qualified(     "0a:00.0") == "0000:0a:00.0", "qualified 3")
   assert(qualified(     "0A:00.0") == "0000:0A:00.0", "qualified 4")
   assert(canonical("0000:01:00.0") ==      "01:00.0", "canonical 1")
   assert(canonical(     "01:00.0") ==      "01:00.0", "canonical 2")
   scan_devices()
   print_device_summary()
end

function print_device_summary ()
   local attrs = {"pciaddress", "model", "interface", "status",
                  "driver", "usable"}
   local fmt = "%-11s %-18s %-10s %-7s %-20s %s"
   print(fmt:format(unpack(attrs)))
   for _,info in ipairs(devices) do
      local values = {}
      for _,attr in ipairs(attrs) do
         table.insert(values, info[attr] or "-")
      end
      print(fmt:format(unpack(values)))
   end
end
