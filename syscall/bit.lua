-- abstract different bit libraries in different lua versions

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math

-- TODO add 64 bit operations here - see test b64 which is currently failing under lua/bit32

local ok, bit = pcall(require, "bit")

if ok then return bit end

local ok, bit32 = pcall(require, "bit32")

bit32.tobit = function(x) return tonumber(x) end -- TODO may need to adjust range
bit32.bswap = function(x)
  return bit32.bor(bit32.lshift(bit32.extract(x, 0, 8), 24),
                   bit32.lshift(bit32.extract(x, 8, 8), 16),
                   bit32.lshift(bit32.extract(x, 16, 8), 8),
                                bit32.extract(x, 24, 8)
  )
end

if ok then return bit32 end

error("no suitable bit library found")

