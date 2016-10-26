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
   if type(x) ~= type(y) then return false end
   if type(x) == 'table' then
      for k, v in pairs(x) do
         if not equal(v, y[k]) then return false end
      end
      for k, _ in pairs(y) do
         if x[k] == nil then return false end
      end
      return true
   elseif type(x) == 'cdata' then
      local size = ffi.sizeof(x)
      if ffi.sizeof(y) ~= size then return false end
      return C.memcmp(x, y, size) == 0
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
   return loadstring("return "..string)()
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

function hexundump(h, n)
   local buf = ffi.new('char[?]', n)
   local i = 0
   for b in h:gmatch('%x%x') do
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

-- Return a function that will return false until duration has elapsed.
-- If mode is 'repeating' the timer will reset itself after returning true,
-- thus implementing an interval timer. Timefun defaults to `C.get_time_ns'.
function timer (duration, mode, timefun)
   timefun = timefun or C.get_time_ns
   local deadline = timefun() + duration
   local function oneshot ()
      return timefun() >= deadline
   end
   local function repeating ()
      if timefun() >= deadline then
         deadline = deadline + duration
         return true
      else return false end
   end
   if mode == 'repeating' then return repeating
   else return oneshot end
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
   function htonl(b) return tonumber(cast('uint32_t', bswap(b))) end
   function htons(b) return rshift(bswap(b), 16) end
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

-- Simple token bucket for rate-limiting of events.  A token bucket is
-- created through
--
--  local tb = token_bucket_new({ rate = <rate> })
--
-- where <rate> is the maximum allowed rate in Hz, which defaults to
-- 10.  Conceptually, <rate> tokens are added to the bucket each
-- second and the bucket can hold no more than <rate> tokens but at
-- least one.
--

local token_bucket = {}
token_bucket.mt = { __index = token_bucket }
token_bucket.default = { rate = 10 }
function token_bucket_new (config)
   local config = config or token_bucket.default
   local tb = setmetatable({}, token_bucket.mt)
   tb:rate(config.rate or token_bucket.default.rate)
   tb._tstamp = C.get_monotonic_time()
   return tb
end

-- The rate can be set with the rate() method at any time, which fills
-- the token bucket an also returns the previous value.  If called
-- with a nil argument, returns the currently configured rate.
function token_bucket:rate (rate)
   if rate ~= nil then
      local old_rate = self._rate
      self._rate = rate
      self._max_tokens = math.max(rate, 1)
      self._tokens = self._max_tokens
      return old_rate
   end
   return self._rate
end

function token_bucket:_update (tokens)
   local now = C.get_monotonic_time()
   local tokens = math.min(self._max_tokens, tokens + self._rate*(now-self._tstamp))
   self._tstamp = now
   return tokens
end

-- The take() method tries to remove <n> tokens from the bucket.  If
-- enough tokens are available, they are subtracted from the bucket
-- and a true value is returned.  Otherwise, the bucket remains
-- unchanged and a false value is returned.  For efficiency, the
-- tokens accumulated since the last call to take() or can_take() are
-- only added if the request can not be fulfilled by the state of the
-- bucket when the method is called.
function token_bucket:take (n)
   local n = n or 1
   local result = false
   local tokens = self._tokens
   if n > tokens then
      tokens = self:_update(tokens)
   end
   if n <= tokens then
      tokens = tokens - n
      result = true
   end
   self._tokens = tokens
   return result
end

-- The can_take() method returns a true value if the bucket contains
-- at least <n> tokens, false otherwise.  The bucket is updated in a
-- layz fashion as described for the take() method.
function token_bucket:can_take (n)
   local n = n or 1
   local tokens = self._tokens
   if n <= tokens then
      return true
   end
   tokens = self:_update(tokens)
   self._tokens = tokens
   return n <= tokens
end

-- Simple rate-limited logging facility.  Usage:
--
--   local logger = lib.logger_new({ rate = <rate>,
--                                   discard_rate = <drate>,
--                                   fh = <fh>,
--                                   flush = true|false,
--                                   module = <module>,
--                                   date = true|false })
--   logger:log(message)
--
-- <rate>   maximum rate of messages per second.  Additional
--          messages are discarded. Default: 10
-- <drate>  maximum rate of logging of the number of discarded
--          messages.  Default: 0.5
-- <fh>     file handle to log to.  Default: io.stdout
-- flush    flush <fh> after each message if true
-- <module> name of the module to include in the message
-- date     include date in messages if true
--
-- The output format is
-- <date> <module>: message
--
-- The logger uses an automatic throttling mechanism to dynamically
-- lower the logging rate when the rate of discarded messages exceeds
-- the maximum log rate by a factor of 5 over one or multiple adjacent
-- intervals of 10 seconds.  For each such interval, the logging rate
-- is reduced by a factor of 2 with a lower bound of 0.1 Hz (i.e. one
-- message per 10 seconds).  For each 10-second interval for which the
-- rate of discarded messages is below the threshold, the logging rate
-- is increased by 1/4 of the original rate, i.e. it takes at least 40
-- seconds to ramp back up to the original rate.
--
-- The tables lib.logger_default and lib.logger_throttle are exposed
-- to the user as part of the API.
logger_default = {
   rate = 10,
   discard_rate = 0.5,
   fh = io.stdout,
   flush = true,
   module = '',
   date = true,
   date_fmt = "%b %d %Y %H:%M:%S ",
}
logger_throttle = {
   interval = 10, -- Sampling interval for discard rate
   excess = 5,   -- Multiple of rate at which to start throttling
   increment = 4, -- Fraction of rate to increase for un-throttling
   min_rate = 0.1, -- Minimum throttled rate
}
local logger = {
   default = logger_default,
   throttle = logger_throttle,
}
logger.mt = { __index = logger }

function logger_new (config)
   local config = config or logger.default
   local l = setmetatable({}, logger.mt)
   _config = setmetatable({}, { __index = logger.default })
   for k, v in pairs(config) do
      assert(_config[k], "Logger: unknown configuration option "..k)
      _config[k] = v
   end
   l._config = _config
   l._tb = token_bucket_new({ rate = _config.rate })
   l._discard_tb = token_bucket_new({ rate = _config.discard_rate })
   l._discards = 0
   local _throttle = {
      discards = 0,
      tstamp = C.get_monotonic_time(),
      rate = _config.rate * logger.throttle.excess,
      increment = _config.rate/logger.throttle.increment,
   }
   l._throttle = setmetatable(_throttle, { __index = logger.throttle })
   l._preamble = (l._config.module and l._config.module..': ') or ''
   return l
end

-- Log message <msg> unless the rate limit is exceeded.  Note that
-- <msg> is evaluated upon the method call in any case, which can have
-- a performance impact even when the message is discarded.  This can
-- be avoided by calling the can_log() method first, i.e.
--
--   if logger:can_log() then
--     logger:log('foo')
--   end
--
-- This framework should have very low processing overhead and should
-- be safe to call even form within packet-processing loops.  The
-- bottleneck currently is the call to clock_gettime().  Care has been
-- taken to make sure that this call is executed at most once in the
-- non-rate limited code path.

function logger:log (msg)
   if self._tb:take(1) then
      local config = self._config
      local throttle  = self._throttle
      throttle.discards = throttle.discards + self._discards
      local date = ''
      if config.date then
         date = os.date(config.date_fmt)
      end
      local preamble = date..self._preamble
      local fh = config.fh
      local now = C.get_monotonic_time()
      local interval = now-throttle.tstamp
      local samples = interval/throttle.interval
      local drate = throttle.discards/interval
      local current_rate = self._tb:rate()
      if self._discards > 0 and self._discard_tb:take(1) then
         fh:write(string.format(preamble.."%d messages discarded\n",
                                self._discards))
         throttle.discards = self._discards
         self._discards = 0
      end
      if samples >= 1 then
         if drate > throttle.rate then
            local min_rate = throttle.min_rate
            if current_rate > min_rate then
               local throttle_rate = math.max(min_rate,
                                              current_rate/2^samples)
               fh:write(string.format(preamble.."message discard rate %.2f exceeds "
                                      .."threshold (%.2f), throttling logging rate to "
                                      .."%.2f Hz%s\n",
                                   drate, throttle.rate, throttle_rate,
                                   (throttle_rate == min_rate and ' (minimum)') or ''))
               self._tb:rate(throttle_rate)
            end
         else
            local configured_rate = config.rate
            if current_rate < configured_rate then
               local throttle_rate = math.min(configured_rate,
                                              current_rate + throttle.increment*samples)
               fh:write(string.format(preamble.."unthrottling logging rate to "
                                      .."%.2f Hz%s\n",
                                   throttle_rate,
                                   (throttle_rate == configured_rate and ' (maximum)') or ''))
               self._tb:rate(throttle_rate)
            end
         end
         throttle.discards = 0
         throttle.tstamp = now
      end
      fh:write(preamble..msg..'\n')
      if config.flush then fh:flush() end
   else
      self._discards = self._discards + 1
   end
end

-- Return true if a message can be logged without being discarded,
-- false otherwise.  In the first case, it is guaranteed that the
-- token bucket for the logging rate-limiter contains at least one
-- token.  In the second case, the rate-limit is hit and the counter
-- of discarded messages is increased.
function logger:can_log ()
   if self._tb:can_take(1) then
      return true
   end
   self._discards = self._discards + 1
   return false
end

-- Wrapper around os.getenv which only returns the variable's value if it
-- is non-empty.
function getenv (name)
   local value = os.getenv(name)
   if value and #value ~= 0 then return value
   else return nil end
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
