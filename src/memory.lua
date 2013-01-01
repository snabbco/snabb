module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

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
   local verbose = options.verbose or false
   print("selftest: physmem")
   local physbase = 0x10000000
   local size     = 0x01000000
   local mem = C.map_physical_ram(physbase, physbase + size, true)
   local virtbase = ffi.cast("uint64_t", mem)
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
   print("OK")
end

