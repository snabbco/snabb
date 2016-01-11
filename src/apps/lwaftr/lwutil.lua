module(..., package.seeall)

local bit = require("bit")
local ffi = require("ffi")

local band, rshift, bswap = bit.band, bit.rshift, bit.bswap
local cast = ffi.cast

local uint16_ptr_t = ffi.typeof("uint16_t*")
local uint32_ptr_t = ffi.typeof("uint32_t*")

function get_ihl_from_offset(pkt, offset)
   local ver_and_ihl = pkt.data[offset]
   return band(ver_and_ihl, 0xf) * 4
end

-- The rd16/wr16/rd32/wr32 functions are provided for convenience.
-- They do NO conversion of byte order; that is the caller's responsibility.
function rd16(offset)
   return cast(uint16_ptr_t, offset)[0]
end

function wr16(offset, val)
   cast(uint16_ptr_t, offset)[0] = val
end

function rd32(offset)
   return cast(uint32_ptr_t, offset)[0]
end

function wr32(offset, val)
   cast(uint32_ptr_t, offset)[0] = val
end

local to_uint32_buf = ffi.new('uint32_t[1]')
local function to_uint32(x)
   to_uint32_buf[0] = x
   return to_uint32_buf[0]
end

function htons(s) return rshift(bswap(s), 16) end
function htonl(s) return to_uint32(bswap(s)) end

function keys(t)
   local result = {}
   for k,_ in pairs(t) do
      table.insert(result, k)
   end
   return result
end

