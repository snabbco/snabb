module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local hugepagesize = 2 * 1024 * 1024

-- Allocate physically contiguous memory that is suitable for DMA.
-- Return a pointer (or nil on failure) and the total number of bytes
-- allocated (which can be more or less than requested).
function dma_alloc (size)
   local page = allocate_huge_page()
   if page == nil then return nil, 0 end
   return page, math.min(hugepagesize, size)
end

-- Try hard to allocate a huge page and return its address.
function allocate_huge_page ()
   for i = 1,3 do
      local page = C.allocate_huge_page(hugepagesize)
      if page ~= nil then  return page  else  reserve_new_page()  end
   end
end

function reserve_new_page ()
   set_hugepages(get_hugepages() + 1)
end

function get_hugepages ()
   local file = io.open("/proc/sys/vm/nr_hugepages", "r")
   local n = file:read('*n')
   file:close()
   return n
end

function set_hugepages (n)
   local file = io.open("/proc/sys/vm/nr_hugepages", "w")
   assert(file:write(tostring(n).."\n") ~= nil)
   file:close()
end

-- From virtual page to physical page
local cache = {}
local page_size = 4096

-- Return the 64-bit physical address of virt_addr.
function map (virt_addr)
   virt_addr = ffi.cast("uint64_t", virt_addr)
   local virt_page = tonumber(virt_addr / page_size)
   local offset   = tonumber(virt_addr % page_size)
   local phys_page = cache[virt_page] or resolve(virt_page)
   return ffi.cast("uint64_t", phys_page * page_size + offset)
end

-- Return (and cache) the physical page number of virtpage.
function resolve (virt_page)
   local phys_page = C.phys_page(virt_page)
   if phys_page == 0 then error("Unable to resolve page " .. virt_page) end
   cache[virt_page] = phys_page
   return phys_page
end

function selftest (options)
   print("selftest: memory")
   local verbose = options.verbose or false
   print("Kernel HugeTLB pages (/proc/sys/vm/nr_hugepages): " .. get_hugepages())
   for i = 1, 4 do
      io.write("  Allocating 1MB from a HugeTLB page: ") io.flush()
      local dmaptr, dmalen = dma_alloc(1024*1024)
      print(tostring(dmaptr)..", "..tostring(dmalen))
      if dmaptr == nil or dmalen ~= 1024*1024 then
         error("Failed to allocate HugeTLB page.")
      end
   end
   print("Kernel HugeTLB pages (/proc/sys/vm/nr_hugepages): " .. get_hugepages())
   print("HugeTLB page allocation OK.")
   local physbase = 0x10000000
   local size     = 0x01000000
   local mem = C.map_physical_ram(physbase, physbase + size, true)
   local virtbase = ffi.cast("uint64_t", mem)
   print("Virtual->Physical mapping test...")
   if verbose then
      print(("%s:%s are the virtual:physical base addresses.")
            :format(bit.tohex(tonumber(virtbase)),
                    bit.tohex(tonumber(physbase))))
      print("Testing mapping with random addresses:")
   end
   math.randomseed(0)
   for i = 1,64 do
      local virt = math.random(tonumber(virtbase), tonumber(virtbase + size))
      local mapped = map(virt)
      local phys   = physbase + (virt - virtbase)
      if (phys == mapped) then
         if verbose then
            io.write(("%s:%s ")
                     :format(bit.tohex(virt), bit.tohex(tonumber(mapped))))
         end
      else
         error(("Error: Mapped %s to %s but expected %s")
               :format(bit.tohex(virt), bit.tohex(tonumber(mapped)),
                       bit.tohex(tonumber(phys))))
      end
      if (verbose and i % 4 == 0) then print() end
   end
   print("Virtual->Physical mapping OK.")
end

