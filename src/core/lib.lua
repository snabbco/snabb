module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C


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

-- Function that should always trigger a LuaJIT "NYI".
-- 
-- That is: no JIT trace should be able to span across a call to
-- trace_barrier().
function trace_barrier (...)
   return {...}
end

function selftest ()
   print("selftest: lib")
   local data = "\x45\x00\x00\x73\x00\x00\x40\x00\x40\x11\xc0\xa8\x00\x01\xc0\xa8\x00\xc7"
   local cs = csum(data, string.len(data))
   assert(cs == 0xb861, "bad checksum: " .. bit.tohex(cs, 4))
   
--    assert(readlink('/etc/rc2.d/S99rc.local') == '../init.d/rc.local', "bad readlink")
--    assert(dirname('/etc/rc2.d/S99rc.local') == '/etc/rc2.d', "wrong dirname")
--    assert(basename('/etc/rc2.d/S99rc.local') == 'S99rc.local', "wrong basename")
end

