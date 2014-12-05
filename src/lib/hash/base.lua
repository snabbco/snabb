-- Abstract base class for hash functions.
--
-- A subclass must define the instance variable "_size" as the number
-- of bits in the output of the hash function.  The standard
-- constructor expects that the hash size is at least 32 and is a
-- multiple thereof.  It allocates a chunk of memory that can hold the
-- output of the hash function and overlays it with a union of arrays
-- of signed and unsigned 8 and 32 bit integers.  If the size is a
-- multiple of 64, the union contains additional arrays of signed and
-- unsigned 64-bit integers.  The union is exposed as a public
-- instance variable named 'h' in the API, allowing the arrays to be
-- accessed as follows, where the prefixes 'u' and 'i' refer to the
-- unsigned and signed variants, respectively.
--
--   hash.h.u8
--   hash.h.i8
--   hash.h.u32
--   hash.h.i32
--   hash.h.u64
--   hash.h.i64
--
-- A subclass must implement the method hash(), which must accept at
-- least two arguments:
-- 
--   data   Pointer to a region of memory where the input is stored
--   length Size of input in bytes
-- 
-- The hash() method must store the result in the 'h' instance
-- variable. For convenience of the caller, the method must return
-- 'h', allowing for direct access like
--
--  local foo = hash:hash(data, l).u32[0]
--

module(..., package.seeall)
local ffi = require("ffi")

local hash = subClass(nil)
hash._name = "hash function"

function hash:new ()
   assert(self ~= hash, "Can't instantiate abstract class hash")
   local o = hash:superClass().new(self)
   assert(o._size and o._size >= 32 and o._size%32 == 0)
   local h_t
   if o._size >= 64 and o._size%64 == 0 then
      h_t = ffi.typeof([[
			     union {
				uint8_t  u8[$];
				int8_t   u8[$];
				uint32_t u32[$];
				int32_t  i32[$];
				uint64_t u64[$];
				int64_t  i64[$];
			     }
		       ]], 
		       o._size/8, o._size/8,
		       o._size/32, o._size/32,
		       o._size/64, o._size/64)
   else
      h_t = ffi.typeof([[
			     union {
				uint8_t  u8[$];
				int8_t  u8[$];
				uint32_t u32[$];
				int32_t  i32[$];
			     }
		       ]],
		       o._size/8, o._size/8,
		       o._size/32, o._size/32)
   end
   o.h = h_t()
   return o
end

function hash:size ()
   return self._size
end

return hash
