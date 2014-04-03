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

do
   --- MAC address handling object.
   -- depends on LuaJIT's 64-bit capabilities,
   -- both for nubmers and bit.* library

   local mac_t = ffi.typeof('union { int64_t bits; uint8_t bytes[6];}')

   local mac_mt = {}
   mac_mt.__index = mac_mt

   function new_mac(m)
      if ffi.istype(mac_t, m) then
         return m
      end
      local macobj = mac_t()
      local i = 0;
      for b in m:gmatch('[0-9a-fA-F][0-9a-fA-F]') do
         macobj.bytes[i] = tonumber(b, 16)
         i = i + 1
      end
      return macobj
   end

   function mac_mt:__tostring()
      return string.format('%02X:%02X:%02X:%02X:%02X:%02X',
         self.bytes[0], self.bytes[1], self.bytes[2],
         self.bytes[3], self.bytes[4], self.bytes[5])
   end

   function mac_mt.__eq(a, b)
      return a.bits == b.bits
   end

   function mac_mt:subbits(i,j)
      local b = bit.rshift(self.bits, i)
      local mask = bit.bnot(bit.lshift(0xffffffffffffLL, j-i))
      return tonumber(bit.band(b, mask))
   end

  mac_t = ffi.metatype(mac_t, mac_mt)
end

--- index set object: keeps a set of indexed values
local NDX_mt = {}
NDX_mt.__index = NDX_mt

-- trivial constructor
function new_index_set(max, name)
   return setmetatable({
      __nxt = 0,
      __max = max,
      __name = name,
   }, NDX_mt)
end

-- add a value to the set
-- if new, returns a new index and true
-- if it already existed, returns given index and false
function NDX_mt:add(v)
   assert(self.__nxt < self.__max, self.__name.." overflow")
   if self[v] then
      return self[v], false
   end
   self[v] = self.__nxt
   self.__nxt = self.__nxt + 1
   return self[v],true
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

function selftest ()
   print("selftest: lib")
   local data = "\x45\x00\x00\x73\x00\x00\x40\x00\x40\x11\xc0\xa8\x00\x01\xc0\xa8\x00\xc7"
   local cs = csum(data, string.len(data))
   assert(cs == 0xb861, "bad checksum: " .. bit.tohex(cs, 4))
   
--    assert(readlink('/etc/rc2.d/S99rc.local') == '../init.d/rc.local', "bad readlink")
--    assert(dirname('/etc/rc2.d/S99rc.local') == '/etc/rc2.d', "wrong dirname")
--    assert(basename('/etc/rc2.d/S99rc.local') == 'S99rc.local', "wrong basename")
   assert(hexdump('\x45\x00\xb6\x7d\x00\xFA\x40\x00\x40\x11'):upper()
         :match('^45.00.B6.7D.00.FA.40.00.40.11$'), "wrong hex dump")
   assert(hexundump('4500 B67D 00FA400040 11', 10)
         =='\x45\x00\xb6\x7d\x00\xFA\x40\x00\x40\x11', "wrong hex undump")

   local macA = new_mac('00-01-02-0a-0b-0c')
   local macB = new_mac('0001020A0B0C')
   local macC = new_mac('0A:0B:0C:00:01:02')
   print ('macA', macA)
   assert (tostring(macA) == '00:01:02:0A:0B:0C', "bad canonical MAC")
   assert (macA == macB, "macA and macB should be equal")
   assert (macA ~= macC, "macA and macC should be different")
   assert (macA:subbits(0,31)==0x0a020100, "low A")
   assert (macA:subbits(32,48)==0x0c0b, ("hi A (%X)"):format(macA:subbits(32,48)))
   assert (macC:subbits(0,31)==0x000c0b0a, "low C")
   assert (macC:subbits(32,48)==0x0201," hi C")

   local ndx_set = new_index_set(4, 'test ndx')
   assert (string.format('%d/%s', ndx_set:add('a'))=='0/true', "indexes start with 0, and is new")
   assert (string.format('%d/%s', ndx_set:add('b'))=='1/true', "second new index")
   assert (string.format('%d/%s', ndx_set:add('c'))=='2/true', "third new")
   assert (string.format('%d/%s', ndx_set:add('b'))=='1/false', "that's an old one")
   assert (string.format('%d/%s', ndx_set:add('a'))=='0/false', "the very first one")
   assert (string.format('%d/%s', ndx_set:add('A'))=='3/true', "almost, but new")
   assert (string.format('%s/%s', pcall(ndx_set.add, ndx_set,'B'))
         :match('^false/core/lib.lua:%d+: test ndx overflow'), 'should overflow')
end

