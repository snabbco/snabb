module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local lib = require("core.lib")
require("core.memory_h")


-- hook variables

dma_alloc = nil         -- (size) => ram_ptr, io_address
allocate_RAM = nil      -- (size) => ram_ptr
ram_to_io_addr = nil    -- (ram_ptr) => io_address

--- ### Serve small allocations from hugepage "chunks"

-- List of all allocated huge pages: {pointer, physical, size, used}
-- The last element is used to service new DMA allocations.
chunks = {}

-- Lowest and highest addresses of valid DMA memory.
-- (Useful information for creating memory maps.)
dma_min_addr, dma_max_addr = false, false

-- Allocate DMA-friendly memory.
-- Return virtual memory pointer, physical address, and actual size.
function dma_alloc (bytes)
   if use_hugetlb then assert(bytes <= huge_page_size) end
   bytes = lib.align(bytes, 128)
   if #chunks == 0 or bytes + chunks[#chunks].used > chunks[#chunks].size then
      allocate_next_chunk()
   end
   local chunk = chunks[#chunks]
   local where = chunk.used
   chunk.used = chunk.used + bytes
   return chunk.pointer + where, chunk.physical + where, bytes
end

-- Add a new chunk.
function allocate_next_chunk ()
   local ptr = assert(allocate_RAM(huge_page_size), "Couldn't allocate a chunk of ram")
   local mem_phy = assert(ram_to_io_addr(ptr, huge_page_size), "Couln't map a chunk of ram to IO address")
   chunks[#chunks + 1] = { pointer = ffi.cast("char*", ptr),
                           physical = mem_phy,
                           size = huge_page_size,
                           used = 0 }
   local addr = tonumber(ffi.cast("uint64_t",ptr))
   dma_min_addr = math.min(dma_min_addr or addr, addr)
   dma_max_addr = math.max(dma_max_addr or 0, addr + huge_page_size)
end

--- ### HugeTLB: Allocate contiguous memory in bulk from Linux

-- Configuration option: Set to false to disable HugeTLB.
use_hugetlb = true

function reserve_new_page ()
   set_hugepages(get_hugepages() + 1)
end

function get_hugepages ()
   return lib.readfile("/proc/sys/vm/nr_hugepages", "*n")
end

function set_hugepages (n)
   lib.writefile("/proc/sys/vm/nr_hugepages", tostring(n))
end

function get_huge_page_size ()
   local meminfo = lib.readfile("/proc/meminfo", "*a")
   local _,_,hugesize = meminfo:find("Hugepagesize: +([0-9]+) kB")
   if hugesize == nil then
      -- Huge pages not available.
      -- Use a reasonable default value, but inhibit HugeTLB allocation.
      use_hugetlb = false
      return 2048*1024
   else
      return tonumber(hugesize) * 1024
   end
end

base_page_size = 4096
-- Huge page size in bytes
huge_page_size = get_huge_page_size()
-- Address bits per huge page (2MB = 21 bits; 1GB = 30 bits)
huge_page_bits = math.log(huge_page_size, 2)

--- ### Physical address translation

function virtual_to_physical (virt_addr)
   virt_addr = ffi.cast("uint64_t", virt_addr)
   local virt_page = tonumber(virt_addr / base_page_size)
   local phys_page = C.phys_page(virt_page) * base_page_size
   if phys_page == 0 then
      error("Failed to resolve physical address of "..tostring(virt_addr))
   end
   local phys_addr = ffi.cast("uint64_t", phys_page + virt_addr % base_page_size)
   return phys_addr
end

--- ### selftest

function selftest (options)
   print("selftest: memory")
   require("lib.hardware.bus")
   if not use_hugetlb then
      print("Skipping test because use_hugetlb = false.")
      os.exit(43)
   end
   print("HugeTLB pages (/proc/sys/vm/nr_hugepages): " .. get_hugepages())
   for i = 1, 4 do
      io.write("  Allocating a "..(huge_page_size/1024/1024).."MB HugeTLB: ")
      io.flush()
      local dmaptr, physptr, dmalen = dma_alloc(huge_page_size)
      print("Got "..(dmalen/1024^2).."MB "..
         "at 0x"..tostring(ffi.cast("void*",tonumber(physptr))))
      ffi.cast("uint32_t*", dmaptr)[0] = 0xdeadbeef -- try a write
      assert(dmaptr ~= nil and dmalen == huge_page_size)
   end
   print("HugeTLB pages (/proc/sys/vm/nr_hugepages): " .. get_hugepages())
   print("HugeTLB page allocation OK.")
end

--- ### module init: `mlock()` at load time

--- This module requires a stable physical-virtual mapping so this is
--- enforced automatically at load-time.

function set_use_physical_memory ()
    ram_to_io_addr = virtual_to_physical
    assert(C.lock_memory() == 0)     -- let's hope it's not needed anymore
end

function set_default_allocator ()
    if use_hugetlb and huge_page_size and lib.can_write("/proc/sys/vm/nr_hugepages") then
        allocate_RAM = function(size)
            for i =1, 3 do
                local page = C.allocate_huge_page(size)
                if page ~= nil then return page else reserve_new_page() end
            end
        end
    else
        allocate_RAM = C.malloc
    end
end
