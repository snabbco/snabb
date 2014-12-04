module(...,package.seeall)

local ffi = require("ffi")
local bit = require("bit")
local band = bit.band

function new (type, size)
   -- size should be power of 2
   print("freelist new", size, bit.bnot(size-1), bit.band(size,bit.bnot(size-1)))
   assert(bit.band(size,bit.bnot(size-1)) == size)

   return { read = 0,
            write = 0,
            max = size,
            -- XXX Better LuaJIT idiom for specifying the array type?
            list = ffi.new(type.."[?]", size) }
end

function add (freelist, element)
   -- Safety check
--   assert(freelist.nfree < freelist.max, "freelist overflow")
   if not full(freelist) then
      freelist.list[freelist.write] = element
      freelist.write = band(freelist.write + 1, freelist.max - 1)
   end
end

function remove (freelist)
   if empty(freelist) then
      return nil
   else
      local t = freelist.list[freelist.read]
      freelist.read = band(freelist.read + 1, freelist.max - 1)
      return t
   end
end

-- Return the number of packets that are ready for read.
function nreadable (freelist)
   if freelist.read > freelist.write then
      return freelist.write + freelist.max - freelist.read
   else
      return freelist.write - freelist.read
   end
end

function nfree (freelist)
   return freelist.max - nreadable(freelist)
end

function empty (freelist)
   return freelist.read == freelist.write
end

-- Return true if the ring is full.
function full (freelist)
   return band(freelist.write + 1, freelist.max - 1) == freelist.read
end
