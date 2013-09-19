module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

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

