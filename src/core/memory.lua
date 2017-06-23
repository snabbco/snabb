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
local shm = require("core.shm")
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
   local fd = assert(syscall.open("/proc/sys/vm/nr_hugepages","rdonly"))
   fd:flock("ex")
   for i = 1, 3 do
      local ok, page = pcall(allocate_huge_page, huge_page_size, true)
      if ok then
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

--- Physical memory allocation

-- Allocate HugeTLB memory pages for DMA. HugeTLB memory is always
-- mapped to a virtual address with a specific scheme:
--
--   virtual_address = physical_address | 0x500000000000ULL
--
-- This makes it possible to resolve physical addresses directly from
-- virtual addresses (remove the tag bits) and to test addresses for
-- validity (check the tag bits).

-- Tag applied to physical addresses to calculate virtual address.
local tag = 0x500000000000ULL

-- virtual_to_physical(ptr) => uint64_t
--
-- Return the physical address of specially mapped DMA memory.
local uint64_t = ffi.typeof("uint64_t")
function virtual_to_physical (virt_addr)
   local u64 = ffi.cast(uint64_t, virt_addr)
   if bit.band(u64, 0x500000000000ULL) ~= 0x500000000000ULL then
      print("Invalid DMA address: 0x"..bit.tohex(u64,12))
      error("DMA address tag check failed")
   end
   return bit.bxor(u64, 0x500000000000ULL)
end

-- function allocate_huge_page(size[, persistent]):
--
-- Map a new HugeTLB page to an appropriate virtual address.
--
-- The page is allocated via the hugetlbfs filesystem
-- /var/run/snabb/hugetlbfs that is mounted automatically.
-- The page has to be file-backed because the Linux kernel seems to
-- not support remap() on anonymous pages.
--
-- Further reading:
--   https://www.kernel.org/doc/Documentation/vm/hugetlbpage.txt
--   http://stackoverflow.com/questions/27997934/mremap2-with-hugetlb-to-change-virtual-address
function allocate_huge_page (size,  persistent)
   ensure_hugetlbfs()
   local tmpfile = "/var/run/snabb/hugetlbfs/alloc."..syscall.getpid()
   local fd = syscall.open(tmpfile, "creat, rdwr", "RWXU")
   assert(fd, "create hugetlb")
   assert(syscall.ftruncate(fd, size), "ftruncate")
   local tmpptr = syscall.mmap(nil, size, "read, write", "shared, hugetlb", fd, 0)
   assert(tmpptr, "mmap hugetlb")
   assert(syscall.mlock(tmpptr, size))
   local phys = resolve_physical(tmpptr)
   local virt = bit.bor(phys, tag)
   local ptr = syscall.mmap(virt, size, "read, write", "shared, hugetlb, fixed", fd, 0)
   local filename = ("/var/run/snabb/hugetlbfs/%012x.dma"):format(tonumber(phys))
   if persistent then
      assert(syscall.rename(tmpfile, filename))
      shm.mkdir(shm.resolve("group/dma"))
      syscall.symlink(filename, shm.root..'/'..shm.resolve("group/dma/"..lib.basename(filename)))
   else
      assert(syscall.unlink(tmpfile))
   end
   syscall.close(fd)
   return ptr, filename
end

function hugetlb_filename (address)
   return ("%012x.dma"):format(virtual_to_physical(address))
end

-- resolve_physical(ptr) => uint64_t
--
-- Resolve the physical address of the given pointer via the kernel.
function resolve_physical (ptr)
   local pagesize = 4096
   local virtpage = ffi.cast("uint64_t", ptr) / pagesize
   local pagemapfd = assert(syscall.open("/proc/self/pagemap", "rdonly"))
   local data = ffi.new("uint64_t[1]")
   syscall.pread(pagemapfd, data, 8, virtpage * 8)
   syscall.close(pagemapfd)
   assert(bit.band(data[0], bit.lshift(1, 63)) ~= 0ULL, "page not present")
   local physpage = bit.band(data[0], 0xFFFFFFFFFFFFF)
   return physpage * pagesize
end

-- Make sure that /var/run/snabb/hugetlbfs is mounted.
function ensure_hugetlbfs ()
   syscall.mkdir("/var/run/snabb/hugetlbfs")
   if not syscall.mount("none", "/var/run/snabb/hugetlbfs", "hugetlbfs", "rw,nosuid,nodev,noexec,relatime,remount") then
      io.write("[mounting /var/run/snabb/hugetlbfs]\n")
      assert(syscall.mount("none", "/var/run/snabb/hugetlbfs", "hugetlbfs", "rw,nosuid,nodev,noexec,relatime"),
             "failed to (re)mount /var/run/snabb/hugetlbfs")
   end
end

-- Deallocate all file-backed shared memory allocated by pid (or other
-- processes in its process group).
--
-- This is an internal API function provided for cleanup during
-- process termination.
function shutdown (pid)
   local dma = shm.children("/"..pid.."/group/dma")
   for _, file in ipairs(dma) do
      local symlink = shm.root.."/"..pid.."/group/dma/"..file
      local realfile = syscall.readlink(symlink)
      syscall.unlink(realfile)
   end
end

-- Setup SIGSEGV handler to automatically map memory from other processes
C.memory_sigsegv_setup(huge_page_size,
                       shm.root..'/'..shm.resolve("group/dma/%012lx.dma"))

--- ### selftest

function selftest (options)
   print("selftest: memory")
   print("Kernel vm.nr_hugepages: " .. syscall.sysctl("vm.nr_hugepages"))
   ensure_hugetlbfs() -- can print a message, let that go first
   local dmapointers = {}
   for i = 1, 4 do
      io.write("  Allocating a "..(huge_page_size/1024/1024).."MB HugeTLB:")
      io.flush()
      local dmaptr, physptr, dmalen = dma_alloc(huge_page_size)
      print("Got "..(dmalen/1024^2).."MB")
      print("    Physical address: 0x" .. bit.tohex(virtual_to_physical(dmaptr), 12))
      print("    Virtual address:  0x" .. bit.tohex(ffi.cast(uint64_t, dmaptr), 12))
      ffi.cast("uint32_t*", dmaptr)[0] = 0xdeadbeef -- try a write
      assert(dmaptr ~= nil and dmalen == huge_page_size)
      table.insert(dmapointers, dmaptr)
   end
   print("Kernel vm.nr_hugepages: " .. syscall.sysctl("vm.nr_hugepages"))
   print("Testing automatic remapping of DMA memory")
   local orig_demand_mappings = C.memory_demand_mappings
   -- First unmap all of the DMA memory
   for _, dmaptr in ipairs(dmapointers) do
      print("    Unmapping " .. tostring(dmaptr))
      assert(syscall.munmap(dmaptr, huge_page_size))
   end
   -- Now touch them all
   for _, dmaptr in ipairs(dmapointers) do
      print("    Writing   ".. tostring(dmaptr))
      dmaptr[0] = 42
   end
   local new_demand_mappings = C.memory_demand_mappings - orig_demand_mappings
   print(("Created %d on-demand memory mappings with SIGSEGV handler."):format(
         new_demand_mappings))
   assert(new_demand_mappings >= #dmapointers)
   -- Now access it and rely on the SIGSEGV handler to 
   print("HugeTLB page allocation OK.")
end

