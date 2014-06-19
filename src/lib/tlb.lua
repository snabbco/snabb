-- Translation Lookaside Buffer.
-- Caches address space translations at page granularity.
-- This implementation has no size limit and never evicts old entries.
module(..., package.seeall)

local ffi = require("ffi")

-- Create a new cache for pagesize-bit pages.
function new (pagesize)
   assert(pagesize >= 12)
   return {pagesize = pagesize}
end

local function u64 (x) return ffi.cast("uint64_t", x) end

-- Add a new mapping to the cache.
function add (tlb, from, to)
   local page = tonumber(bit.rshift(u64(from), tlb.pagesize))
   local offset = u64(to) - u64(from)
   tlb[page] = offset
end

-- Cache lookup. Retrun translated address or nil.
function lookup (tlb, pointer)
   local address = u64(pointer)
   local page = tonumber(bit.rshift(address, tlb.pagesize))
   if tlb[page] then
      local address = u64(pointer) + tlb[page]
      return ffi.cast(ffi.typeof(pointer), address)
   end
end

-- Print all TLB cache entries.
function dump (tlb)
   print("TLB dump:")
   for k, v in pairs(tlb) do
      if type(k) == 'number' then
         print(("page %s\tdelta %s"):format(bit.tohex(u64(k),16), bit.tohex(u64(v),16)))
      end
   end
end

function selftest ()
   local pagesize = 21
   local tab = new(pagesize)
   local p = function(x) return ffi.cast("char*", x) end
   for i = 1, 16 do
      local from = p(bit.lshift(u64(i), 56) + i)
      local to   = p(bit.lshift(u64(i), 48) + i)
      add(tab, from, to)
      assert(lookup(tab, from) == to)
      assert(lookup(tab, from + 100) == to + 100)
   end
   dump(tab)
   print("table hits OK.")
   assert(lookup(tab, 0xFF00000000000000ULL) == nil)
   print("table miss OK.")
end

