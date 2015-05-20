module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
local getopt = require("lib.lua.alt_getopt")
local syscall = require("syscall")
require("core.clib_h")

-- Returns true if x and y are structurally similar (isomorphic).
function equal (x, y)
   if type(x) ~= type(y) then return false end
   if type(x) == 'table' then
      for k, v in pairs(x) do
         if not equal(v, y[k]) then return false end
      end
      for k, _ in pairs(y) do
         if x[k] == nil then return false end
      end
      return true
   else
      return x == y
   end
end

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

-- Load Lua value from string.
function load_string (string)
   return loadstring("return "..string)
end

-- Read a Lua conf from file and return value.
function load_conf (file)
   return dofile(file)
end

-- Store Lua representation of value in file.
function store_conf (file, value)
   local indent = 0
   local function print_indent (stream)
      for i = 1, indent do stream:write(" ") end
   end
   local function print_value (value, stream)
      local  type = type(value)
      if     type == 'table'  then
         indent = indent + 2
         stream:write("{\n")
         if #value == 0 then
            for key, value in pairs(value) do
               print_indent(stream)
               stream:write(key, " = ")
               print_value(value, stream)
               stream:write(",\n")
            end
         else
            for _, value in ipairs(value) do
               print_indent(stream)
               print_value(value, stream)
               stream:write(",\n")
            end
         end
         indent = indent - 2
         print_indent(stream)
         stream:write("}")
      elseif type == 'string' then
         stream:write(("%q"):format(value))
      else
         stream:write(("%s"):format(value))
      end
   end
   local stream = assert(io.open(file, "w"))
   stream:write("return ")
   print_value(value, stream)
   stream:write("\n")
   stream:close()
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
   if type(n) == 'cdata' then
      n = tonumber(n)
   end
   if n ~= n then return "NaN" end
   local left,num,right = string.match(n,'^([^%d]*%d)(%d*)(.-)$')
   return left..(num:reverse():gsub('(%d%d%d)','%1,'):reverse())..right
end

function random_data(length)
   result = ""
   math.randomseed(os.time())
   for i=1,length do
      result = result..string.char(math.random(0, 255))
   end
   return result
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
   if len % 2 == 1 then sum = sum + bit.lshift(ptr[len-1], 1) end
   return sum
end

function finish_csum (sum)
   while bit.band(sum, 0xffff) ~= sum do
      sum = bit.band(sum + bit.rshift(sum, 16), 0xffff)
   end
   return bit.band(bit.bnot(sum), 0xffff)
end


function malloc (etype)
   if type(etype) == 'string' then
      etype = ffi.typeof(etype)
   end
   local size = ffi.sizeof(etype)
   local ptr = memory.dma_alloc(size)
   return ffi.cast(ffi.typeof("$*", etype), ptr)
end


-- deepcopy from http://lua-users.org/wiki/CopyTable
-- with naive ctype support
function deepcopy(orig)
   local orig_type = type(orig)
   local copy
   if orig_type == 'table' then
      copy = {}
      for orig_key, orig_value in next, orig, nil do
         copy[deepcopy(orig_key)] = deepcopy(orig_value)
      end
      setmetatable(copy, deepcopy(getmetatable(orig)))
   elseif orig_type == 'ctype' then
      copy = ffi.new(ffi.typeof(orig))
      ffi.copy(copy, orig, ffi.sizeof(orig))
   else -- number, string, boolean, etc
      copy = orig
   end
   return copy
end

-- 'orig' must be an array, not a sparse array (hash)
function array_copy(orig)
   local result = {}
   for i=1,#orig do
      result[i] = orig[i]
   end
   return result
end

-- endian conversion helpers written in Lua
-- avoid C function call overhead while using C.xxxx counterparts
if ffi.abi("be") then
   -- nothing to do
   function htonl(b) return b end
   function htons(b) return b end
else
   function htonl(b) return bit.bswap(b) end
   function htons(b) return bit.rshift(bit.bswap(b), 16) end
end
ntohl = htonl
ntohs = htons

-- Process ARGS using ACTIONS with getopt OPTS/LONG_OPTS.
-- Return the remaining unprocessed arguments.
function dogetopt (args, actions, opts, long_opts)
   local opts,optind,optarg = getopt.get_ordered_opts(args, opts, long_opts)
   for i, v in ipairs(opts) do
      if actions[v] then 
	 actions[v](optarg[i]) 
      else
	 error("unimplemented option: " .. v) 
      end
   end
   local rest = {}
   for i = optind, #args do table.insert(rest, args[i]) end
   return rest
end

-- based on http://stackoverflow.com/a/15434737/1523491
function have_module (name)
   if package.loaded[name] then
      return true
   else
      for _, searcher in ipairs(package.loaders) do
	 local loader = searcher(name)
	 if type(loader) == 'function' then
	    package.preload[name] = loader
	    return true
	 end
      end
      return false
   end
end

-- Exit with an error if we are not running as root.
function root_check (message)
   if syscall.geteuid() ~= 0 then
      print(message or "error: must run as root")
      main.exit(1)
   end
end

-- Simple rate-limited logging facility.  Usage:
--
--   local logger = lib.logger_new({ rate = <rate>,
--                                   fh = <fh>,
--                                   flush = true|false,
--                                   module = <module>,
--                                   date = true|false })
--   logger:log(message)
--
-- <rate> maximum rate of messages per second.  Additional
--        messages are discarded. Default: 10
-- <fh>   file handle to log to.  Default: io.stdout
-- flush  flush <fh> after each message if true
-- <module> name of the module to include in the message
-- date   include date in messages if true
--
-- The output format is
-- <date> <module>: message
--
local logger = {}
-- Default configuration
logger.config = { rate = 10,
		  fh = io.stdout,
		  flush = true,
		  module = '',
		  date = true }

function logger_new (config)
   local config = config or {}
   local l = { config = {} }
   setmetatable(l.config, { __index = logger.config })
   for k, v in pairs(config) do
      assert(logger.config[k], "Unkown logger configuration "..k)
      l.config[k] = v
   end
   l.tstamp = C.get_unix_time()
   l.token_bucket = l.config.rate
   l.discard = 0
   return setmetatable(l, { __index = logger })
end

function logger:log (msg)
   local rate = self.config.rate
   local fh = self.config.fh
   local flush = self.config.flush
   local date = ''
   if self.config.date then
      date = os.date("%b %Y %H:%M:%S ")
   end
   local now = C.get_unix_time()
   local new_tokens = rate*(now-self.tstamp)
   self.token_bucket = math.min(rate, self.token_bucket+new_tokens)
   if self.token_bucket >= 1 then
      if self.discard > 0 then
	 fh:write(date..self.discard.." messages discarded\n")
	 self.discard = 0
      end
      msg = date..(self.config.module and self.config.module..': '
			     or '')..msg..'\n'
      fh:write(msg)
      if flush then fh:flush() end
      self.token_bucket = self.token_bucket-1
   else
      self.discard = self.discard+1
   end
   self.tstamp = now
end

function selftest ()
   print("selftest: lib")
   print("Testing equal")
   assert(true == equal({foo="bar"}, {foo="bar"}))
   assert(false == equal({foo="bar"}, {foo="bar", baz="foo"}))
   assert(false == equal({foo="bar", baz="foo"}, {foo="bar"}))
   print("Testing load/store_conf")
   local conf = { foo="1", bar=42, arr={2,"foo",4}}
   local testpath = "/tmp/snabb_lib_test_conf"
   store_conf(testpath, conf)
   assert(equal(conf, load_conf(testpath)), "Either `store_conf' or `load_conf' failed.")
   print("Testing csum")
   local data = "\x45\x00\x00\x73\x00\x00\x40\x00\x40\x11\xc0\xa8\x00\x01\xc0\xa8\x00\xc7"
   local cs = csum(data, string.len(data))
   assert(cs == 0xb861, "bad checksum: " .. bit.tohex(cs, 4))
   
--    assert(readlink('/etc/rc2.d/S99rc.local') == '../init.d/rc.local', "bad readlink")
--    assert(dirname('/etc/rc2.d/S99rc.local') == '/etc/rc2.d', "wrong dirname")
--    assert(basename('/etc/rc2.d/S99rc.local') == 'S99rc.local', "wrong basename")
   print("Testing hex(un)dump")
   assert(hexdump('\x45\x00\xb6\x7d\x00\xFA\x40\x00\x40\x11'):upper()
         :match('^45.00.B6.7D.00.FA.40.00.40.11$'), "wrong hex dump")
   assert(hexundump('4500 B67D 00FA400040 11', 10)
         =='\x45\x00\xb6\x7d\x00\xFA\x40\x00\x40\x11', "wrong hex undump")
end
