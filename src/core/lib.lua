-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
local getopt = require("lib.lua.alt_getopt")
local syscall = require("syscall")
require("core.clib_h")
local bit = require("bit")
local band, bor, bnot, lshift, rshift, bswap =
   bit.band, bit.bor, bit.bnot, bit.lshift, bit.rshift, bit.bswap
local tonumber = tonumber -- Yes, this makes a performance difference.
local cast = ffi.cast

-- Returns true if x and y are structurally similar (isomorphic).
function equal (x, y)
   if type(x) ~= type(y) then
      return false
   elseif x == y then
      return true
   elseif type(x) == 'table' then
      if getmetatable(x) then return false end
      if getmetatable(y) then return false end
      for k, v in pairs(x) do
         if not equal(v, y[k]) then return false end
      end
      for k, _ in pairs(y) do
         if x[k] == nil then return false end
      end
      return true
   elseif type(x) == 'cdata' then
      if x == y then return true end
      if ffi.typeof(x) ~= ffi.typeof(y) then return false end
      local size = ffi.sizeof(x)
      if ffi.sizeof(y) ~= size then return false end
      return C.memcmp(x, y, size) == 0
   else
      return false
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
   return f:close() and result
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

-- Load Lua value from string.
function load_string (string)
   return loadstring("return "..string)()
end

-- Read a Lua conf from file and return value.
function load_conf (file)
   return dofile(file)
end

-- Store Lua representation of value in file.
function print_object (value, stream)
   stream = stream or io.stdout
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
   print_value(value, stream)
   stream:write("\n")
end
function store_conf (file, value)
   local stream = assert(io.open(file, "w"))
   stream:write("return ")
   print_object(value, stream)
   stream:close()
end

-- Return a bitmask using the values of `bitset' as indexes.
-- The keys of bitset are ignored (and can be used as comments).
-- Example: bits({RESET=0,ENABLE=4}, 123) => 1<<0 | 1<<4 | 123
function bits (bitset, basevalue)
   local sum = basevalue or 0
   for _,n in pairs(bitset) do
      sum = bor(sum, lshift(1, n))
   end
   return sum
end

-- Return true if bit number 'n' of 'value' is set.
function bitset (value, n)
   return band(value, lshift(1, n)) ~= 0
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

function hexundump(h, n, error)
   local buf = ffi.new('char[?]', n)
   local i = 0
   for b in h:gmatch('%s*(%x%x)') do
      buf[i] = tonumber(b, 16)
      i = i+1
      if i >= n then break end
   end
   if error ~= false then
      assert(i == n, error or "Wanted "..n.." bytes, but only got "..i)
   end
   return ffi.string(buf, n)
end

function comma_value(n) -- credit http://richard.warburton.it
   if type(n) == 'cdata' then
      n = string.match(tostring(n), '^-?([0-9]+)U?LL$') or tonumber(n)
   end
   if n ~= n then return "NaN" end
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

-- Return a throttle function.
--
-- The throttle returns true at most once in any <seconds> time interval.
function throttle (seconds)
   local deadline = engine.now()
   return function ()
      if engine.now() > deadline then
         deadline = engine.now() + seconds
         return true
      else
         return false
      end
   end
end

-- Return a timeout function.
--
-- The timeout function returns true only if <seconds> have elapsed
-- since it was created.
function timeout (seconds)
   local deadline = engine.now() + seconds
   return function () return engine.now() > deadline end
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
      sum = sum + lshift(ptr[i], 8) + ptr[i+1]
   end
   if len % 2 == 1 then sum = sum + lshift(ptr[len-1], 1) end
   return sum
end

function finish_csum (sum)
   while band(sum, 0xffff) ~= sum do
      sum = band(sum + rshift(sum, 16), 0xffff)
   end
   return band(bnot(sum), 0xffff)
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
  -- htonl is unsigned, matching the C version and expectations.
  -- Wrapping the return call in parenthesis avoids the compiler to do
  -- a tail call optimization.  In LuaJIT when the number of successive
  -- tail calls is higher than the loop unroll threshold, the
  -- compilation of a trace is aborted.  If the trace was long that
  -- can result in poor performance.
   function htonl(b) return (tonumber(cast('uint32_t', bswap(b)))) end
   function htons(b) return (rshift(bswap(b), 16)) end
end
ntohl = htonl
ntohs = htons

-- Manipulation of bit fields in uint{8,16,32)_t stored in network
-- byte order.  Using bit fields in C structs is compiler-dependent
-- and a little awkward for handling endianness and fields that cross
-- byte boundaries.  We're bound to the LuaJIT compiler, so I guess
-- this would be save, but masking and shifting is guaranteed to be
-- portable.

local bitfield_endian_conversion = 
   { [16] = { ntoh = ntohs, hton = htons },
     [32] = { ntoh = ntohl, hton = htonl }
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
   local mask = lshift(2^nbits-1, shift)
   local imask = bnot(mask)
   if value then
      field = bor(band(field, imask),
                  band(lshift(value, shift), mask))
      if conv then
         struct[member] = conv.hton(field)
      else
         struct[member] = field
      end
   else
      return rshift(band(field, mask), shift)
   end
end

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

-- Wrapper around os.getenv which only returns the variable's value if it
-- is non-empty.
function getenv (name)
   local value = os.getenv(name)
   if value and #value ~= 0 then return value
   else return nil end
end

-- Wrapper around execve.
function execv(path, argv)
   local env = {}
   for k, v in pairs(syscall.environ()) do table.insert(env, k.."="..v) end
   return syscall.execve(path, argv or {}, env)
end

-- Return an array of random bytes.
function random_bytes_from_dev_urandom (count)
   local bytes = ffi.new(ffi.typeof('uint8_t[$]', count))
   local f = syscall.open('/dev/urandom', 'rdonly')
   local written = 0
   while written < count do
      written = written + assert(f:read(bytes, count-written))
   end
   f:close()
   return bytes
end

function random_bytes_from_math_random (count)
   local bytes = ffi.new(ffi.typeof('uint8_t[$]', count))
   for i = 0,count-1 do bytes[i] = math.random(0, 255) end
   return bytes
end

function randomseed (seed)
   seed = tonumber(seed)
   if seed then
      local msg = 'Using deterministic random numbers, SNABB_RANDOM_SEED=%d.\n'
      io.stderr:write(msg:format(seed))
      -- When setting a seed, use deterministic random bytes.
      random_bytes = random_bytes_from_math_random
   else
      -- Otherwise use /dev/urandom.
      seed = ffi.cast('uint32_t*', random_bytes_from_dev_urandom(4))[0]
      random_bytes = random_bytes_from_dev_urandom
   end
   math.randomseed(seed)
   return seed
end

function random_data (length)
   return ffi.string(random_bytes(length), length)
end

local lower_case = "abcdefghijklmnopqrstuvwxyz"
local upper_case = lower_case:upper()
local extra = "0123456789_-"
local alphabet = table.concat({lower_case, upper_case, extra})
assert(#alphabet == 64)
function random_printable_string (entropy)
   -- 64 choices in our alphabet, so 6 bits of entropy per byte.
   entropy = entropy or 160
   local length = math.floor((entropy - 1) / 6) + 1
   local bytes = random_data(length)
   local out = {}
   for i=1,length do
      out[i] = alphabet:byte(bytes:byte(i) % 64 + 1)
   end
   return string.char(unpack(out))
end

-- Compiler barrier.
-- Prevents LuaJIT from moving load/store operations over this call.
-- Any FFI call is sufficient to achieve this, see:
-- http://www.freelists.org/post/luajit/Compiler-loadstore-barrier-volatile-pointer-barriers-in-general,3
function compiler_barrier ()
   C.nop()
end

-- parse: Given ARG, a table of parameters or nil, assert that from
-- CONFIG all of the required keys are present, fill in any missing values for
-- optional keys, and error if any unknown keys are found.
--
-- ARG := { key=vaue, ... }
-- CONFIG := { key = {[required=boolean], [default=value]}, ... }
function parse (arg, config)
   local ret = {}
   if arg == nil then arg = {} end
   for k, o in pairs(config) do
      assert(arg[k] ~= nil or not o.required, "missing required parameter '"..k.."'")
   end
   for k, v in pairs(arg) do
      assert(config[k], "unrecognized parameter '"..k.."'")
      ret[k] = v
   end
   for k, o in pairs(config) do
      if ret[k] == nil then ret[k] = o.default end
   end
   return ret
end

function set(...)
   local ret = {}
   for k, v in pairs({...}) do ret[v] = true end
   return ret
end

-- Check if 'name' is a kernel network interface.
function is_iface (name)
   local f = io.open('/proc/net/dev')
   for line in f:lines() do
      local iface = line:match("^%s*(%w+):")
      if iface and iface == name then f:close() return true end
   end
   f:close()
   return false
end

function selftest ()
   print("selftest: lib")
   print("Testing equal")
   assert(true == equal({foo="bar"}, {foo="bar"}))
   assert(false == equal({foo="bar"}, {foo="bar", baz="foo"}))
   assert(false == equal({foo="bar", baz="foo"}, {foo="bar"}))
   print("Testing load_string")
   assert(equal(load_string("{1,2}"), {1,2}), "load_string failed.")
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
   print("Testing ntohl")
   local raw_val = 0xf0d0b0f0
   assert(ntohl(raw_val) > 0, "ntohl must be unsigned")
   assert(ntohl(ntohl(raw_val)) == raw_val, 
      "calling ntohl twice must return the original value")

   -- test parse
   print("Testing parse")
   local function assert_parse_equal (arg, config, expected)
      assert(equal(parse(arg, config), expected))
   end
   local function assert_parse_error (arg, config)
      assert(not pcall(parse, arg, config))
   end

   local req = {required=true}
   local opt = {default=42}

   assert_parse_equal({a=1, b=2}, {a=req, b=req, c=opt}, {a=1, b=2, c=42})
   assert_parse_equal({a=1, b=2}, {a=req, b=req}, {a=1, b=2})
   assert_parse_equal({a=1, b=2, c=30}, {a=req, b=req, c=opt, d=opt}, {a=1, b=2, c=30, d=42})
   assert_parse_equal({a=1, b=2, d=10}, {a=req, b=req, c=opt, d=opt}, {a=1, b=2, c=42, d=10})
   assert_parse_equal({d=10}, {c=opt, d=opt}, {c=42, d=10})
   assert_parse_equal({}, {c=opt}, {c=42})
   assert_parse_equal({d=false}, {d=opt}, {d=false})
   assert_parse_equal({d=nil}, {d=opt}, {d=42})
   assert_parse_equal({a=false, b=2}, {a=req, b=req}, {a=false, b=2})
   assert_parse_equal(nil, {}, {})

   assert_parse_error({}, {a=req, b=req, c=opt})
   assert_parse_error({d=30}, {a=req, b=req, d=opt})
   assert_parse_error({a=1}, {a=req, b=req})
   assert_parse_error({b=1}, {a=req, b=req})
   assert_parse_error({a=nil, b=2}, {a=req, b=req})
   assert_parse_error({a=1, b=nil}, {a=req, b=req})
   assert_parse_error({a=1, b=2, d=10, e=100}, {a=req, b=req, d=opt})
   assert_parse_error({a=1, b=2, c=4}, {a=req, b=req})
   assert_parse_error({a=1, b=2}, {})
   assert_parse_error(nil, {a=req})
end
