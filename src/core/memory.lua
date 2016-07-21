-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

-- For more information about huge pages checkout:
-- * HugeTLB - Large Page Support in the Linux kernel
--   http://linuxgazette.net/155/krishnakumar.html)
-- * linux/Documentation/vm/hugetlbpage.txt
--  https://www.kernel.org/doc/Documentation/vm/hugetlbpage.txt)

local ffi = require("ffi")
local C = ffi.C
local syscall = require("syscall")

local lib = require("core.lib")
require("core.memory_h")

--- ### Serve small allocations from hugepage "chunks"

-- List of all allocated huge pages: {pointer, physical, size, used}
-- The last element is used to service new DMA allocations.
chunks = {}

-- Allocate DMA-friendly memory.
-- Return virtual memory pointer, physical address, and actual size.
function dma_alloc (bytes,  align)
   align = align or 128
   assert(bytes <= huge_page_size)
   -- Get current chunk of memory to allocate from
   if #chunks == 0 then allocate_next_chunk() end
   local chunk = chunks[#chunks]
   -- Skip allocation forward pointer to suit alignment
   chunk.used = lib.align(chunk.used, align)
   -- Need a new chunk to service this allocation?
   if chunk.used + bytes > chunk.size then
      allocate_next_chunk()
      chunk = chunks[#chunks]
   end
   -- Slice out the memory we need
   local where = chunk.used
   chunk.used = chunk.used + bytes
   return chunk.pointer + where, chunk.physical + where, bytes
end

-- Add a new chunk.
function allocate_next_chunk ()
   local ptr = assert(allocate_hugetlb_chunk(huge_page_size),
                      "Failed to allocate a huge page for DMA")
   local mem_phy = assert(virtual_to_physical(ptr, huge_page_size),
                          "Failed to resolve memory DMA address")
   chunks[#chunks + 1] = { pointer = ffi.cast("char*", ptr),
                           physical = mem_phy,
                           size = huge_page_size,
                           used = 0 }
end

--- ### HugeTLB: Allocate contiguous memory in bulk from Linux

function allocate_hugetlb_chunk ()
   local fd, err = syscall.open("/proc/sys/vm/nr_hugepages","rdonly")
   assert(fd, tostring(err))
   fd:flock("ex")
   for i =1, 3 do
      local page = C.allocate_huge_page(huge_page_size)
      if page ~= nil then
         fd:flock("un")
         fd:close()
         return page
      else
         reserve_new_page()
      end
   end
end

function reserve_new_page ()
   -- Check that we have permission
   lib.root_check("error: must run as root to allocate memory for DMA")
   -- Is the kernel shm limit too low for huge pages?
   if huge_page_size > tonumber(lib.firstline("/proc/sys/kernel/shmmax")) then
      -- Yes: fix that
      local old = lib.writefile("/proc/sys/kernel/shmmax", tostring(huge_page_size))
      io.write("[memory: Enabling huge pages for shm: ",
               "sysctl kernel.shmmax ", old, " -> ", huge_page_size, "]\n")
   else
      local have = tonumber(lib.firstline("/proc/sys/vm/nr_hugepages"))
      local want = have + 1
      lib.writefile("/proc/sys/vm/nr_hugepages", tostring(want))
      io.write("[memory: Provisioned a huge page: sysctl vm.nr_hugepages ", have, " -> ", want, "]\n")
   end
end

function get_huge_page_size ()
   local meminfo = lib.readfile("/proc/meminfo", "*a")
   local _,_,hugesize = meminfo:find("Hugepagesize: +([0-9]+) kB")
   assert(hugesize, "HugeTLB available")
   return tonumber(hugesize) * 1024
end

base_page_size = 4096
-- Huge page size in bytes
huge_page_size = get_huge_page_size()
-- Address bits per huge page (2MB = 21 bits; 1GB = 30 bits)
huge_page_bits = math.log(huge_page_size, 2)

--- ### Physical address translation

local uint64_t = ffi.typeof("uint64_t")
function virtual_to_physical (virt_addr)
   local u64 = ffi.cast(uint64_t, virt_addr)
   if bit.band(u64, 0x500000000000ULL) ~= 0x500000000000ULL then
      print("Invalid DMA address: 0x"..bit.tohex(u64,12))
      error("DMA address tag check failed")
   end
   return bit.bxor(u64, 0x500000000000ULL)
end

--- ### selftest

function selftest (options)
   print("selftest: memory")
   print("Kernel vm.nr_hugepages: " .. syscall.sysctl("vm.nr_hugepages"))
   for i = 1, 4 do
      io.write("  Allocating a "..(huge_page_size/1024/1024).."MB HugeTLB: ")
      io.flush()
      local dmaptr, physptr, dmalen = dma_alloc(huge_page_size)
      print("Got "..(dmalen/1024^2).."MB")
      print("    Physical address: 0x" .. bit.tohex(virtual_to_physical(dmaptr), 12))
      print("    Virtual address:  0x" .. bit.tohex(ffi.cast(uint64_t, dmaptr), 12))
      ffi.cast("uint32_t*", dmaptr)[0] = 0xdeadbeef -- try a write
      assert(dmaptr ~= nil and dmalen == huge_page_size)
   end
   print("Kernel vm.nr_hugepages: " .. syscall.sysctl("vm.nr_hugepages"))
   print("HugeTLB page allocation OK.")
end

