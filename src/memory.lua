module(...,package.seeall)

local lib = require("lib")
local ffi = require("ffi")
local C = ffi.C
require("snabb_h")

--- ### High level allocate() and free().

buffer_size = 4096
freelist = {}

-- Return a free packet buffer.
function allocate ()
   return (table.remove(freelist) or dma_alloc(buffer_size)), buffer_size
end

-- Free a packet buffer for later reuse.
function free (buffer)
   table.insert(freelist, buffer)
end

--- ### Chunks.
---
--- Memory is allocated from the operating system one "chunk" at a
--- time. A chunk is an arbitrary-sized block of physically contiguous
--- memory. Chunks are then then sliced up to serve individual
--- allocations.

-- Current chunk: pointer, physical address, remaining size.
local chunk_ptr, chunk_phy, chunk_size

-- Array of {address = virtaddr, size = bytes} tables for each DMA region.
dma_regions = {}

-- Install a new chunk of memory at a specific physical memory address.
-- Mostly useful if you have reserved memory using 'linux memmap=16M$0x10000000'
-- Then you can use install(0x10000000, 16*1024*1024)
function install (physical, size)
   local ptr = C.map_physical_ram(physical, physical+size, true)
   if ptr == nil then error("Error installing RAM at 0x"..bit.tohex(physical)) end
   add_chunk(ffi.cast("char*",ptr), physical, size)
end

-- Install a new chunk of memory from a dynamically allocated HugeTLB page.
-- This happens automatically when more memory is needed.
function install_huge_page ()
   local page = allocate_huge_page()
   if page == nil then error("Failed to allocate HugeTLB page for DMA.") end
   add_chunk(ffi.cast("char*",page), map(page), huge_page_size)
end

-- Add a new chunk of memory for the next DMA allocations.
function add_chunk (ptr, physical, size)
   local address = tonumber(ffi.cast("uint64_t", ptr))
   dma_regions[#dma_regions + 1] = {address = address, size = size}
   chunk_ptr, chunk_phy, chunk_size = ptr, physical, size
end

--- DMA is allocated from the current chunk, which is replaced once it
--- becomes too small.

-- Allocate physically contiguous memory that is suitable for DMA.
-- Returns three values when successful:
--   Virtual memory address as a void* pointer for use within Lua (or nil).
--   Physical memory address as a uint64_t for passing to hardware.
--   Actual number of bytes allocated, which can be different than requested.
-- Returns nil on failure.
function dma_alloc (size)
   if size % 128 ~= 0 then
      -- Keep 128-byte alignment
      size = size + 128 - (size % 128)
   end
   if chunk_ptr == nil or (size > chunk_size and size <= huge_page_size) then
      -- Get more memory
      install_huge_page()
   end
   if chunk_size >= size then
      local ptr, phy = chunk_ptr, chunk_phy
      chunk_ptr, chunk_phy = chunk_ptr + size, chunk_phy + size
      chunk_size = chunk_size - size
      return ptr, phy, size
   else
      error("Failed to allocate " .. lib.comma_value(size) .. " bytes of DMA memory.")
   end
end

--- ### HugeTLB ("huge page") allocation from the Linux kernel
---
--- This is a way to dynamically allocate large (typically 2-4MB)
--- areas of physically contiguous memory.
---
--- See <http://www.kernel.org/doc/Documentation/vm/hugetlbpage.txt>

function allocate_huge_page ()
   for i = 1,3 do
      local page = C.allocate_huge_page(huge_page_size)
      if page ~= nil then  return page  else  reserve_new_page()  end
   end
end

function reserve_new_page ()
   set_hugepages(get_hugepages() + 1)
end

function get_hugepages ()
   return lib.readfile("/proc/sys/vm/nr_hugepages", "*n")
end

function set_hugepages (n)
   lib.writefile("/proc/sys/vm/nr_hugepages", tostring(n))
end

--- ### Physical address translation

-- Return the physical address of virt_addr as a number.
function map (virt_addr)
   virt_addr = ffi.cast("uint64_t", virt_addr)
   local virt_page = tonumber(virt_addr / base_page_size)
   local offset    = tonumber(virt_addr % base_page_size)
   local phys_page = C.phys_page(virt_page)
   if phys_page == 0 then resolve_error(virt_addr) end
   return tonumber(ffi.cast("uint64_t", phys_page * base_page_size + offset))
end

function resolve_error (virt_addr)
   print("  0x"..bit.tohex(tonumber(virt_addr)).." did not resolve with active DMA regions:")
   for _,d in ipairs(dma_regions) do
      io.write(("  0x%s - 0x%s [%d KB] "):format(
                  bit.tohex(tonumber(d.address)),
                  bit.tohex(tonumber(d.address+d.size)),
                  d.size/1024))
      if virt_addr >= d.address and virt_addr <= d.address + d.size then
         io.write("<-- address belongs in this range\n")
      else
         io.write("(no match)\n")
      end
   end
   error("Failed to resolve physical address of 0x"..bit.tohex(tonumber(virt_addr)))
end

--- Sizes of normal and huge pages in the host kernel.

base_page_size = 4096
huge_page_size =
   (function ()
       local meminfo = lib.readfile("/proc/meminfo", "*a")
       local _,_,hugesize = meminfo:find("Hugepagesize: +([0-9]+) kB")
       return tonumber(hugesize) * 1024
    end)()

function selftest (options)
   print("selftest: memory")
   options = options or {}
   local verbose = options.verbose or false
   print("Kernel HugeTLB pages (/proc/sys/vm/nr_hugepages): " .. get_hugepages())
   for i = 1, 4 do
      io.write("  Allocating a "..(huge_page_size/1024/1024).."MB HugeTLB: ")
      io.flush()
      local dmaptr, physptr, dmalen = dma_alloc(huge_page_size)
      print("Got "..(dmalen/1024^2).."MB at 0x"..bit.tohex(tonumber(physptr)))
      ffi.cast("uint32_t*", dmaptr)[0] = 0xdeadbeef -- make sure the memory works
      if dmaptr == nil or dmalen ~= huge_page_size then
         error("Failed to allocate HugeTLB page.")
      end
   end
   print("Kernel HugeTLB pages (/proc/sys/vm/nr_hugepages): " .. get_hugepages())
   print("HugeTLB page allocation OK.")
end

function module_init ()
   print("memory initialized")
   assert(C.lock_memory() == 0)
end

module_init()
