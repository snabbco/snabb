module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local base_page_size = 4096
local huge_page_size =
   (function ()
       local meminfo = lib.readfile("/proc/meminfo", "*a")
       local _,_,hugesize = meminfo:find("Hugepagesize: +([0-9]+) kB")
       return tonumber(hugesize) * 1024
    end)()

-- Allocate physically contiguous memory that is suitable for DMA.
-- Returns three values when successful:
--   Virtual memory address as a void* pointer for use within Lua (or nil).
--   Physical memory address as a uint64_t for passing to hardware.
--   Actual number of bytes allocated, which can be different than requested.
-- Returns nil on failure.
function dma_alloc (size)
   local page = allocate_huge_page()
   if page == nil then return nil end
   return page, map(page), math.min(huge_page_size, size)
end

-- Return the 64-bit physical address of virt_addr.
function map (virt_addr)
   virt_addr = ffi.cast("uint64_t", virt_addr)
   local virt_page = tonumber(virt_addr / base_page_size)
   local offset    = tonumber(virt_addr % base_page_size)
   local phys_page = resolve(virt_page)
   return tonumber(ffi.cast("uint64_t", phys_page * base_page_size + offset))
end

-- Return the physical page number of virtpage.
function resolve (virt_page)
   local phys_page = C.phys_page(virt_page)
   if phys_page == 0 then error("Unable to resolve page " .. virt_page) end
   return phys_page
end

---- HugeTLB ("huge page") support.

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

function selftest (options)
   print("selftest: memory")
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

