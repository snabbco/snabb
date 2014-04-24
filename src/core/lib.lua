module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
require("core.clib_h")

function can_open(filename, mode)
    mode = mode or 'r'
    local f = io.open(filename, mode)
    if f == nil then return false end
    f:close()
    return true
end

function can_read(filename)
    return can_open(filename, 'r')
end

function can_write(filename)
    return can_open(filename, 'w')
end

--- Return `command` in the Unix shell and read `what` from the result.
function readcmd (command, what)
   local f = io.popen(command)
   local value = f:read(what)
   f:close()
   return value
end

function readfile (filename, what)
   local f = io.open(filename, "r")
   if f == nil then error("Unable to open file: " .. filename) end
   local value = f:read(what)
   f:close()
   return value
end

function writefile (filename, value)
   local f = io.open(filename, "w")
   if f == nil then error("Unable to open file: " .. filename) end
   local result = f:write(value)
   f:close()
   return result
end

function readlink (path)
    local buf = ffi.new("char[?]", 512)
    local len = C.readlink(path, buf, 512)
    if len < 0 then return nil, ffi.errno() end
    return ffi.string(buf, len)
end

function dirname(path)
    if not path then return path end
    
    local buf = ffi.new("char[?]", #path+1)
    ffi.copy(buf, path)
    local ptr = C.dirname(buf)
    return ffi.string(ptr)
end

function basename(path)
    if not path then return path end
    
    local buf = ffi.new("char[?]", #path+1)
    ffi.copy(buf, path)
    local ptr = C.basename(buf)
    return ffi.string(ptr)
end

-- Return the name of the first file in `dir`.
function firstfile (dir)
   return readcmd("ls -1 "..dir.." 2>/dev/null", "*l")
end

function firstline (filename) return readfile(filename, "*l") end

function files_in_directory (dir)
   local files = {}
   for line in io.popen('ls -1 "'..dir..'" 2>/dev/null'):lines() do
      table.insert(files, line)
   end
   return files
end

-- Return a bitmask using the values of `bitset' as indexes.
-- The keys of bitset are ignored (and can be used as comments).
-- Example: bits({RESET=0,ENABLE=4}, 123) => 1<<0 | 1<<4 | 123
function bits (bitset, basevalue)
   local sum = basevalue or 0
   for _,n in pairs(bitset) do
	 sum = bit.bor(sum, bit.lshift(1, n))
   end
   return sum
end

-- Return true if bit number 'n' of 'value' is set.
function bitset (value, n)
   return bit.band(value, bit.lshift(1, n)) ~= 0
end

-- Manipulation of bit fields in uint{8,16,32)_t stored in network
-- byte order.  Using bit fields in C structs is compiler-dependent
-- and a little awkward for handling endianness and fields that cross
-- byte boundaries.  We're bound to the LuaJIT compiler, so I guess
-- this would be save, but masking and shifting is guaranteed to be
-- portable.  Performance could be an issue, though.

local bitfield_endian_conversion = 
   { [16] = { ntoh = C.ntohs, hton = C.htons },
     [32] = { ntoh = C.ntohl, hton = C.htonl }
  }

function bitfield(size, struct, member, offset, nbits, value)
   local conv = bitfield_endian_conversion[size]
   local field
   if conv then
      field = conv.ntoh(struct[member])
   else
      field = struct[member]
   end
   local shift = size-(nbits+offset)
   local mask = bit.lshift(2^nbits-1, shift)
   local imask = bit.bnot(mask)
   if value then
      field = bit.bor(bit.band(field, imask), bit.lshift(value, shift))
      if conv then
	 struct[member] = conv.hton(field)
      else
	 struct[member] = field
      end
   else
      return bit.rshift(bit.band(field, mask), shift)
   end
end

-- Iterator factory for splitting a string by pattern
-- (http://lua-users.org/lists/lua-l/2006-12/msg00414.html)
function string:split(pat)
  local st, g = 1, self:gmatch("()("..pat..")")
  local function getter(self, segs, seps, sep, cap1, ...)
    st = sep and seps + #sep
    return self:sub(segs, (seps or 0) - 1), cap1 or sep, ...
  end
  local function splitter(self)
    if st then return getter(self, st, g()) end
  end
  return splitter, self
end

--- Hex dump and undump functions

function hexdump(s)
   if #s < 1 then return '' end
   local frm = ('%02X '):rep(#s-1)..'%02X'
   return string.format(frm, s:byte(1, #s))
end

function hexundump(h, n)
   local buf = ffi.new('char[?]', n)
   local i = 0
   for b in h:gmatch('[0-9a-fA-F][0-9a-fA-F]') do
      buf[i] = tonumber(b, 16)
      i = i+1
      if i >= n then break end
   end
   return ffi.string(buf, n)
end

function comma_value(n) -- credit http://richard.warburton.it
   local left,num,right = string.match(n,'^([^%d]*%d)(%d*)(.-)$')
   return left..(num:reverse():gsub('(%d%d%d)','%1,'):reverse())..right
end

-- Return a table for bounds-checked array access.
function bounds_checked (type, base, offset, size)
   type = ffi.typeof(type)
   local tptr = ffi.typeof("$ *", type)
   local wrap = ffi.metatype(ffi.typeof("struct { $ _ptr; }", tptr), {
				__index = function(w, idx)
					     assert(idx < size)
					     return w._ptr[idx]
					  end,
				__newindex = function(w, idx, val)
						assert(idx < size)
						w._ptr[idx] = val
					     end,
			     })
   return wrap(ffi.cast(tptr, ffi.cast("uint8_t *", base) + offset))
end

-- Return a function that will return false until NS nanoseconds have elapsed.
function timer (ns)
   local deadline = C.get_time_ns() + ns
   return function () return C.get_time_ns() >= deadline end
end

-- Loop until the function `condition` returns true.
function waitfor (condition)
   while not condition() do C.usleep(100) end
end

function yesno (flag)
   if flag then return 'yes' else return 'no' end
end

-- Increase value to be a multiple of size (if it is not already).
function align (value, size)
   if value % size == 0 then
      return value
   else
      return value + size - (value % size)
   end
end

function waitfor2(name, test, attempts, interval)
   io.write("Waiting for "..name..".")
   for count = 1,attempts do
      if test() then
         print(" ok")
          return
      end
      C.usleep(interval)
      io.write(".")
      io.flush()
   end
   print("")
   error("timeout waiting for " .. name)
end

-- Return "the IP checksum" of ptr:len.
--
-- NOTE: Checksums should seldom be computed in software. Packets
-- carried over hardware ethernet (e.g. 82599) should be checksummed
-- in hardware, and packets carried over software ethernet (e.g.
-- virtio) should be flagged as not requiring checksum verification.
-- So consider it a "code smell" to call this function.
function csum (ptr, len)
   return finish_csum(update_csum(ptr, len))
end

function update_csum (ptr, len,  csum0)
   ptr = ffi.cast("uint8_t*", ptr)
   local sum = csum0 or 0LL
   for i = 0, len-2, 2 do
      sum = sum + bit.lshift(ptr[i], 8) + ptr[i+1]
   end
   if len % 2 == 1 then sum = sum + bit.lshift(ptr[len-1]) end
   return sum
end

function finish_csum (sum)
   while bit.band(sum, 0xffff) ~= sum do
      sum = bit.band(sum + bit.rshift(sum, 16), 0xffff)
   end
   return bit.band(bit.bnot(sum), 0xffff)
end

function malloc (type)
   local ffi_type = ffi.typeof(type)
   local size = ffi.sizeof(ffi_type)
   local ptr = C.malloc(size)
   return ffi.cast(ffi.typeof("$*", ffi_type), ptr)
end
