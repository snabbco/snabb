-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

-- Round-robin database (RRD) library for Snabb.  See README.rrd.md for usage.

local ffi = require("ffi")
local S = require("syscall")
local lib = require("core.lib")
local shm = require("core.shm")
local mem = require("lib.stream.mem")
local file = require("lib.stream.file")

function now()
   local tv = S.gettimeofday()
   return tonumber(tv.tv_sec) + tonumber(tv.tv_usec) * 1e-6
end

local RRD = {}

local rrd_cookie = "RRD\0"
local rrd_version = "0003\0"
local float_cookie = 8.642135E130

local fixed_header_t = ffi.typeof [[struct {
   char cookie[4];
   char version[5];
   double float_cookie;
   uint64_t source_count;
   uint64_t archive_count;
   uint64_t seconds_per_pdp;
   uint64_t unused[10];
}]]

local source_types = lib.set('COUNTER', 'GAUGE')
local consolidation_functions = lib.set('AVERAGE', 'MIN', 'MAX', 'LAST')

-- The bit that's after the header, that depends on the shape of the RRD
-- file.
local variable_header_t_cache = {}
local function variable_header_t(source_count, archive_count)
   local k = string.format('%dx%d', source_count, archive_count)
   if variable_header_t_cache[k] then return variable_header_t_cache[k] end
   local templ = [[struct {
      struct {
         char name[20];
         char type[20];
         uint64_t heartbeat;
         double min;
         double max;
         uint64_t unused[7];
      } data_sources[$]; /* One for each data source. */
      struct {
         char cf[20];
         uint64_t row_count;
         uint64_t pdps_per_cdp;
         double min_coverage; /* Fraction of a CDP that must be known. */
         uint64_t unused[9];
      } archives[$]; /* One for each archive (RRA). */
      struct {
         int64_t seconds;
         int64_t useconds;
      } last_update;
      struct {
         union {
            /* To compute a rate value from counters, the RRD format
               stores the last reading.  Weirdly, the stock RRD tool
               uses an ascii representation in a 30-byte buffer.  For
               our purposes, we just alias the front part of it with raw
               data.  */
            struct {
               uint64_t counter;
               uint8_t is_known;
            } raw;
            char as_chars[30];
         } last_reading;
         uint64_t unknown_count;
         double diff;
         uint64_t unused[8];
      } pdp_prep[$]; /* One for each data source. */
      struct {
         double value;
         /* How many unknown pdp were integrated. This and the min_coverage
            will decide if this is going to be a UNKNOWN or a valid value. */
         uint64_t unknown_count;
         uint64_t unused[8];
      } cdp_prep[$]; /* One for each data source and archive.  */
      uint64_t current_row[$]; /* One for each archive. */
   }]]
   local t = ffi.typeof(templ, source_count, archive_count,
                        source_count, source_count * archive_count,
                        archive_count)
   variable_header_t_cache[k] = t
   return t
end

-- Nota bene: in the variable header above, we diverge from the upstream
-- RRD format for the "pdp_prep" and "cdp_prep" areas, but in a
-- compatible way; the sections take up the same amount of space in the
-- file, and they aren't accessed except when adding a new reading to
-- the RRD, which is Snabb's job.  Other data access (e.g. graph
-- creation) goes direct to the archives (to the finished CDPs stored in
-- the RRAs).

local archive_t_cache = {}
local function archive_t(source_count, row_count)
   local k = string.format('%dx%d', source_count, row_count)
   if archive_t_cache[k] then return archive_t_cache[k] end
   local t = ffi.typeof('struct { struct { double values[$]; } rows[$]; }',
                        source_count, row_count)
   archive_t_cache[k] = t
   return t
end

local function ptr_to(t) return ffi.typeof('$*', t) end

function open_mem(ptr, size, filename)
   local rrd = {ptr=ptr, size=size, filename=filename}
   ptr = ffi.cast('uint8_t*', ptr)
   local function read(t)
      assert(size >= ffi.sizeof(t))
      local ret = ffi.cast(ptr_to(t), ptr)
      ptr, size = ptr + ffi.sizeof(t), size - ffi.sizeof(t)
      return ret
   end
   rrd.fixed = read(fixed_header_t)
   assert(ffi.string(rrd.fixed.cookie, 4) == rrd_cookie)
   assert(ffi.string(rrd.fixed.version, 5) == rrd_version)
   assert(rrd.fixed.float_cookie == float_cookie)
   rrd.seconds_per_pdp = tonumber(rrd.fixed.seconds_per_pdp)
   rrd.var = read(variable_header_t(tonumber(rrd.fixed.source_count),
                                    tonumber(rrd.fixed.archive_count)))
   rrd.archives = {}
   for i=0, tonumber(rrd.fixed.archive_count) - 1 do
      rrd.archives[i] = read(archive_t(tonumber(rrd.fixed.source_count),
                                       tonumber(rrd.var.archives[i].row_count)))
   end
   assert(size == 0)
   return setmetatable(rrd, {__index=RRD})
end

function open_file(filename, writable)
   local file_mode, mmap_perms = 'rdonly', 'read'
   if writable then file_mode, mmap_perms = 'rdwr', 'read, write' end
   local fd = assert(S.open(filename, file_mode))
   local stat = S.fstat(fd)
   local len = stat and stat.size
   local ptr = assert(S.mmap(nil, len, mmap_perms, "shared", fd, 0))
   fd:close()
   ffi.gc(ptr, function (ptr) S.munmap(ptr, len) end)
   return open_mem(ptr, len, filename)
end

function open_shm(name, writable)
   return open_file(shm.root..'/'..shm.resolve(name), writable)
end

local function partial_pdp_time(t, seconds_per_pdp)
   return t % seconds_per_pdp
end

local function partial_cdp_pdps(t, seconds_per_pdp, pdps_per_cdp)
   return math.floor((t % (seconds_per_pdp * pdps_per_cdp)) / seconds_per_pdp)
end

local function parse_interval(dt)
   if type(dt) == 'number' then
      assert(dt > 0)
      return math.ceil(dt)
   end
   assert(type(dt) == 'string')
   local n, m = dt:match('^([1-9][0-9]*)([smhdwMy])$')
   local f = {s=1, m=60, h=60*60, d=24*60*60,
              w=7*24*60*60, M=30*24*60*60, y=365*24*60*60}
   return tonumber(n) * f[m]
end

local rrd_params = {
   sources={required=true},
   archives={required=true},
   base_interval={default=1}
}

local source_params = {
   name={required=true},
   type={default='counter'},
   interval={}, -- default to base interval
   min={default=0/0},
   max={default=0/0}
}

local archive_params = {
   cf={default='average'},
   duration={required=true},
   interval={}, -- default to base interval
   min_coverage={default=0.5}
}

function new(arg)
   local stream = mem.tmpfile()
   local fixed = fixed_header_t()
   ffi.copy(fixed.cookie, rrd_cookie, #rrd_cookie)
   ffi.copy(fixed.version, rrd_version, #rrd_version)
   fixed.float_cookie = float_cookie
   arg = lib.parse(arg, rrd_params)
   local base_interval = parse_interval(arg.base_interval)
   local source_count, archive_count = #arg.sources, #arg.archives
   fixed.source_count, fixed.archive_count = source_count, archive_count
   fixed.seconds_per_pdp = base_interval
   stream:write_struct(fixed_header_t, fixed)
   local var_t = variable_header_t(source_count, archive_count)
   local var = var_t()
   for i,source in ipairs(arg.sources) do
      source = lib.parse(source, source_params)
      local s = var.data_sources[i-1]
      assert(string.len(source.name) < ffi.sizeof(s.name))
      s.name = source.name
      assert(string.len(source.type) < ffi.sizeof(s.type))
      assert(source_types[source.type:upper()])
      s.type = source.type:upper()
      s.heartbeat = parse_interval(source.interval or base_interval)
      s.min, s.max = source.min, source.max
   end
   for i,archive in ipairs(arg.archives) do
      archive = lib.parse(archive, archive_params)
      local a = var.archives[i-1]
      assert(consolidation_functions[archive.cf:upper()])
      a.cf = archive.cf:upper()
      local duration = parse_interval(archive.duration)
      local interval = parse_interval(archive.interval or base_interval)
      assert(interval >= base_interval)
      assert(duration > interval)
      a.pdps_per_cdp = math.floor(interval / base_interval)
      interval = tonumber(a.pdps_per_cdp) * base_interval
      a.row_count = math.ceil(duration / interval)
      a.min_coverage = archive.min_coverage
      assert(a.min_coverage >= 0 and a.min_coverage <= 1)
   end
   local t = now()
   var.last_update.seconds = math.floor(t)
   var.last_update.useconds = (t - math.floor(t)) * 1e6
   for i=0,source_count-1 do
      local pdp = var.pdp_prep[i]
      pdp.last_reading.raw.is_known = 0
      pdp.unknown_count = partial_pdp_time(
         var.last_update.seconds, base_interval)
      pdp.diff = 0/0
   end
   for i=0,archive_count-1 do
      for j=0,source_count-1 do
         local cdp = var.cdp_prep[i*source_count + j]
         cdp.value = 0/0
         cdp.unknown_count = partial_cdp_pdps(t, base_interval,
                                              tonumber(var.archives[i].pdps_per_cdp))
      end
   end
   for i=0,archive_count-1 do
      var.current_row[i] = 0
   end
   stream:write_struct(var_t, var)
   for i=0,archive_count-1 do
      local t = archive_t(source_count, tonumber(var.archives[i].row_count))
      local archive = t()
      for row=0,tonumber(var.archives[i].row_count)-1 do
         for source=0,source_count-1 do
            archive.rows[row].values[source] = 0/0
         end
      end
      stream:write_struct(t, archive)
   end
   local len = stream:seek()
   stream:seek('set', 0)
   local ptr = ffi.new('uint8_t[?]', len)
   stream:read_bytes_or_error(ptr, len)
   return open_mem(ptr, len)
end

function create_file(filename, arg)
   local rrd = new(arg)
   -- File might already exists if directory is a link.
   local _, fd = pcall(S.open, filename, "rdwr, excl", '0664')
   if not fd then
      fd = assert(S.open(filename, "creat, rdwr, excl", '0664'))
   end
   local f = file.fdopen(fd, 'wronly', filename)
   f:write_bytes(rrd.ptr, rrd.size)
   f:flush_output()
   local ptr = assert(S.mmap(nil, rrd.size, "read, write", "shared", fd, 0))
   f:close()
   ffi.gc(ptr, function (ptr) S.munmap(ptr, rrd.size) end)
   return open_mem(ptr, rrd.size)
end

function create_shm(name, arg)
   local path = shm.resolve(name)
   shm.mkdir(lib.dirname(path))
   return create_file(shm.root..'/'..path, arg)
end

function dump(rrd, stream)
   stream:write_bytes(rrd.ptr, rrd.size)
   stream:flush_output()
end

function dump_file(rrd, filename)
   local f = file.open(filename, 'w')
   dump(rrd, f)
   f:close()
end

function last_update(rrd)
   local secs = tonumber(rrd.var.last_update.seconds)
   local usecs = tonumber(rrd.var.last_update.useconds)
   return secs + usecs * 1e-6
end

function isources(rrd)
   local function iter(rrd, i)
      i = i + 1
      if i >= rrd.fixed.source_count then return nil end
      local s = rrd.var.data_sources[i]
      local name, typ = ffi.string(s.name), ffi.string(s.type):lower()
      return i, name, typ, tonumber(s.heartbeat), s.min, s.max
   end
   return iter, rrd, -1
end

function iarchives(rrd)
   local function iter(rrd, i)
      i = i + 1
      if i >= rrd.fixed.archive_count then return nil end
      local a = rrd.var.archives[i]
      local cf = ffi.string(a.cf):lower()
      local rows, pdps_per_cdp, xff = a.row_count, a.pdps_per_cdp, a.min_coverage
      return i, cf, tonumber(rows), tonumber(pdps_per_cdp), xff
   end
   return iter, rrd, -1
end

-- Return all readings at time T, grouped by source name and then by
-- consolidation function.  If T is positive, it is treated as an
-- absolute time.  Otherwise it's relative to the last-update time.
function ref(rrd, t)
   local last = last_update(rrd)
   -- Transform t to be "number of seconds in the past".
   if t < 0 then t = -t else t = last - t end
   local ret = {}
   if t < 0 then return ret end
   for i, cf, rows, window, xff in iarchives(rrd) do
      local interval = window * tonumber(rrd.fixed.seconds_per_pdp)
      local offset = math.floor(t / interval)
      if offset < rows then
         local row = (tonumber(rrd.var.current_row[i]) - offset) % rows
         local values = rrd.archives[i].rows[row].values
         for j, name, typ, h, min, max in isources(rrd) do
            local v = values[j]
            if ret[name] == nil then ret[name] = {type=typ, cf={}} end
            if ret[name].cf[cf] == nil then ret[name].cf[cf] = {} end
            table.insert(ret[name].cf[cf], {interval=interval, value=v})
         end
      end
   end
   for name,source in pairs(ret) do
      for cf,readings in pairs(source.cf) do
         table.sort(readings, function(a,b) return a.interval<b.interval end)
      end
   end
   return ret
end

local function isnan(x) return x~=x end

local function compute_diff(pdp, v, typ, dt, heartbeat_interval, lo, hi)
   if v == nil then return 0/0, 0/0 end
   local diff, rate = 0/0, 0/0
   if typ == 'counter' then
      local prev = pdp.last_reading.raw
      if dt < heartbeat_interval and prev.is_known ~= 0 then
         diff = tonumber(v - prev.counter)
         rate = diff / dt
      end
      prev.is_known, prev.counter = 1, v
   elseif typ == 'gauge' then
      if dt < heartbeat_interval then diff, rate = v * dt, v end
   else error('unexpected kind', typ) end
   if rate < lo or rate > hi then return 0/0, 0/0 end
   return diff, rate
end

local function update_pdp(pdp, diff, secs_per_pdp, pre, dt)
   local dt_in_pdp = math.min(dt, secs_per_pdp - pre)
   if isnan(diff) then
      pdp.unknown_count = pdp.unknown_count + dt_in_pdp
   elseif isnan(pdp.diff) then
      pdp.diff = diff * dt_in_pdp / dt
   else
      pdp.diff = pdp.diff + diff * dt_in_pdp / dt
   end
end

local function compute_pdp_value(pdp, secs_per_pdp, dt, heartbeat_interval)
   -- This condition comes from upstream rrdtool.
   local unknown = tonumber(pdp.unknown_count)
   if dt < heartbeat_interval and unknown < secs_per_pdp/2 then
      return pdp.diff / tonumber(secs_per_pdp - unknown)
   else
      return 0/0
   end
end

local function update_cdp(cdp, pdp_value, cf, pdp_pre, pdp_advance,
                          pdps_per_cdp, xff)
   local pdp_advance_in_cdp = math.min(pdp_advance, pdps_per_cdp - pdp_pre)
   -- Update the CDP that was being filled up, then fill any
   -- intermediate slots with 
   if isnan(pdp_value) then
      cdp.unknown_count = cdp.unknown_count + pdp_advance_in_cdp
   end
   if cdp.unknown_count > pdps_per_cdp * xff then
      cdp.value = 0/0
   elseif cf == 'average' then
      if not isnan(pdp_value) then
         if isnan(cdp.value) then cdp.value = 0 end
         cdp.value = cdp.value + pdp_value * pdp_advance_in_cdp
      end
   elseif cf == 'max' then
      if isnan(cdp.value) then cdp.value = pdp_value
      elseif isnan(pdp_value) then -- pass
      else cdp.value = math.max(cdp.value, pdp_value) end
   elseif cf == 'min' then
      if isnan(cdp.value) then cdp.value = pdp_value
      elseif isnan(pdp_value) then -- pass
      else cdp.value = math.min(cdp.value, pdp_value) end
   elseif cf == 'last' then
      cdp.value = pdp_value
   else error('bad cf', cf) end
end

local function compute_cdp_value(cdp, cf, pdps_per_cdp)
   if cf == 'average' then
      return cdp.value / tonumber(pdps_per_cdp - cdp.unknown_count)
   end
   return cdp.value
end

local function reset_cdp(cdp, pdp_post, pdp_value)
   if isnan(pdp_value) or pdp_post == 0 then
      cdp.value = 0/0
      cdp.unknown_count = pdp_post
   elseif cf == 'average' then
      cdp.value = pdp_value * pdp_post
      cdp.unknown_count = 0
   else
      cdp.value = pdp_value
      cdp.unknown_count = 0
   end
end

-- Add a reading, consisting of a map from source names to values.
function add(rrd, values, t)
   if t == nil then t = now() end
   local t0 = last_update(rrd)
   local dt = t - t0; assert(dt >= 0)
   local sec_per_pdp = rrd.seconds_per_pdp
   local dt_pre = partial_pdp_time(t0, sec_per_pdp)
   local dt_post = partial_pdp_time(t, sec_per_pdp)
   local pdp_advance = math.floor((dt + dt_pre) / sec_per_pdp)
   for i, name, typ, h, lo, hi in isources(rrd) do
      local pdp = rrd.var.pdp_prep[i]
      local diff, rate = compute_diff(pdp, values[name], typ, dt, h, lo, hi)
      update_pdp(pdp, diff, sec_per_pdp, dt_pre, dt)

      -- If we made a new PDP, use it to update corresponding CDPs.
      if pdp_advance > 0 then
         local pdp_value = compute_pdp_value(pdp, sec_per_pdp, dt, h)
         
         for j, cf, rows, pdps_per_cdp, xff in iarchives(rrd) do
            local cdp = rrd.var.cdp_prep[j*rrd.fixed.source_count+i]
            local pdp_pre = partial_cdp_pdps(t0, sec_per_pdp, pdps_per_cdp)
            update_cdp(cdp, pdp_value, cf, pdp_pre, pdp_advance,
                       pdps_per_cdp, xff)

            local cdp_advance = math.floor((pdp_pre+pdp_advance)/pdps_per_cdp)
            if cdp_advance > 0 then
               local value = compute_cdp_value(cdp, cf, pdps_per_cdp)
               local archive, row = rrd.archives[j], rrd.var.current_row[j]
               for _=1,math.min(cdp_advance, rows+1) do
                  row = (row + 1) % rows
                  archive.rows[row].values[i] = value
                  -- FIXME: RRDtool fills in any subsequent CDPs with
                  -- the last PDP.  Perhaps instead we should fill in
                  -- with NaN.
                  value = pdp_value
               end
               rrd.var.current_row[j] = row
               local pdp_post = partial_cdp_pdps(t, sec_per_pdp, pdps_per_cdp)
               reset_cdp(cdp, pdp_post, pdp_value)
            end
         end

         if isnan(diff) then
            pdp.diff, pdp.unknown_count = 0/0, dt_post
         else
            pdp.diff, pdp.unknown_count = diff * dt_post/dt, 0
         end
      end
   end
   rrd.var.last_update.seconds = t
   rrd.var.last_update.useconds = (t - math.floor(t)) * 1e6
end

RRD.last_update = last_update
RRD.isources, RRD.iarchives = isources, iarchives
RRD.ref, RRD.add = ref, add
RRD.dump, RRD.dump_file = dump, dump_file

function selftest()
   print('selftest: lib.rrd')
   local rrd = new {
      sources={{name='foo', type='counter'}},
      archives={{cf='average', duration='1h', interval='10s'}},
      base_interval='2s'
   }
   -- Round to nearest 20s so that we are crossing the boundaries in a
   -- uniform way.
   local t = math.ceil(rrd:last_update()/20)*20
   for i=0,40 do rrd:add({foo=42+i},t+0.75*i) end
   for i=0,40 do
      for name,source in pairs(rrd:ref(t+0.75*i)) do
         for cf,values in pairs(source.cf) do
            for _,x in ipairs(values) do
               print(t, name, source.type, cf, x.interval, x.value)
            end
         end
      end
   end
   print('selftest: ok')
end
