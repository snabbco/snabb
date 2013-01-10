module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local base_page_size = 4096
local huge_page_size = 2 * 1024 * 1024

-- Allocate physically contiguous memory that is suitable for DMA.
-- Return a pointer (or nil on failure) and the total number of bytes
-- allocated (which can be more or less than requested).
function dma_alloc (size)
   local page = allocate_huge_page()
   if page == nil then return nil, 0 end
   return page, math.min(huge_page_size, size)
end

-- Try hard to allocate a huge page and return its address.
function allocate_huge_page ()
   for i = 1,3 do
      local page = C.allocate_huge_page(huge_page_size)
      map(page)
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
local sizes = {}

-- Return the 64-bit physical address of virt_addr.
function map (virt_addr)
   virt_addr = ffi.cast("uint64_t", virt_addr)
   local virt_page = tonumber(virt_addr / base_page_size)
   local offset   = tonumber(virt_addr % base_page_size)
   local phys_page = cache[virt_page] or resolve(virt_page)
   return ffi.cast("uint64_t", phys_page * base_page_size + offset)
end

-- Return (and cache) the physical page number of virtpage.
function resolve (virt_page)
   local phys_page = physical_page(virt_page)
   if phys_page == nil then error("Unable to resolve page " .. virt_page) end
   cache[virt_page] = phys_page
   local size = page_size(virt_page)
   sizes[size] = (sizes[size] or 0) + 1
   return phys_page
end

--- ## Extracting information about memory from /proc/self/pagemap

function physical_page (virt_page) return pagemap_info(virt_page) % 2^56 end

function page_size (virt_page)
   local info = pagemap_info(virt_page)
   local pageshift = tonumber((info / 2^55) % 2^6)
   return 2^pageshift
end

function pagemap_info (virt_page)
   local info = C.pagemap_info(virt_page)
   local mapped = info >= 2^63
   if mapped then return info else return nil end
end

function selftest (options)
   print("selftest: memory")
   local verbose = options.verbose or false
   print("Kernel HugeTLB pages (/proc/sys/vm/nr_hugepages): " .. get_hugepages())
   for i = 1, 4 do
      io.write("  Allocating a "..(huge_page_size/1024/1024).."MB HugeTLB page: ") io.flush()
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
   if verbose then
      print("Page size tallys:")
      for size,count in pairs(sizes) do
         print(size,count)
      end
   end

end

