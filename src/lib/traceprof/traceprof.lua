-- traceprof.lua: Low-level trace profiler
-- 
-- Traceprof analyzes the time spent in JIT-compiled traces.  It is an
-- alternative to 'jit.p' with fewer features and based on a simpler
-- and (hopefully) more accurate sampling method.
-- 
-- API:
--   start(): Start profiling.
--   stop():  Stop profiling and print a report.
-- ... and start() has some undocumented optional parameters too.
--
-- Here is an example report:
--
--     traceprof report (recorded 659/659 samples):
--      50% TRACE  20      (14/4)   rate_limiter.lua:82
--      13% TRACE  12:LOOP          basic_apps.lua:26
--      10% TRACE  14               rate_limiter.lua:73
--       3% TRACE  14:LOOP          rate_limiter.lua:73
--       2% TRACE  18:LOOP          basic_apps.lua:82
--       1% TRACE  22      (12/13)  basic_apps.lua:25
--       1% TRACE  25      (20/5)   link.lua:70
-- 
-- The report includes some useful information:
-- 
-- * Which traces are hotspots? (Cross reference with -jdump)
-- * Where does each trace begin? (Source code line)
-- * How to traces connect? Side traces show (PARENT/EXIT).
-- * How much time is spent in the "LOOP" part of a trace vs outside?
-- 
-- Traceprof uses an interval timer to periodically write the CPU
-- Instruction Pointer value to a log (array). The timer fires every 1
-- millisecond (default) and invokes a tiny C signal handler to write
-- the next value.
-- 
-- This log is analyzed after measurement in a separate reporting
-- step. The logged Instruction Pointer values are compared with the
-- machine code addresses of all compiled traces (and their loop offsets).
-- 
-- Traceprof was originally written due to confusion about
-- interpreting the results of 'jit.p' and not understanding exactly
-- how its sampling method works.
-- 
-- Future work:
-- 
-- * Handle JIT "flush" event when existing traces are dropped.
-- * Dump annotated IR/mcode for hot traces (like -jdump).

module(..., package.seeall)

local ffi = require("ffi")
local dump = require("jit.dump")
local jutil = require("jit.util")

require("lib.traceprof.traceprof_h")

local log
local logsize
local starttime

function start (maxsamples, interval_usecs)
   -- default: 1ms interval and 8MB (16 minute) buffer
   maxsamples     = maxsamples or 1e6
   interval_usecs = interval_usecs or 1e3
   logsize = maxsamples
   log = ffi.new("uint64_t[?]", maxsamples)
   ffi.C.traceprof_start(log, maxsamples, interval_usecs)
end

function stop ()
   local total = ffi.C.traceprof_stop()
   local nsamples = math.min(logsize, total)
   print(("traceprof report (recorded %d/%d samples):"):format(nsamples, total))
   report(log, nsamples)
end

function report (samples, nsamples)
   -- Combine individual samples into a table of counts.
   local counts = {}
   for i = 0, nsamples-1 do
      local ip = tonumber(samples[i])
      counts[ip] = (counts[ip] or 0) + 1
   end
   -- Collect what is known about all existing traces.
   local traces = {}
   for tracenr = 1, 1e5 do
      local info = jutil.traceinfo(tracenr)
      if info then traces[tracenr] = info else break end
      local extra = dump.info[tracenr]
      if extra then for k,v in pairs(extra) do info[k] = v end end
   end
   -- Match samples up with traces.
   local results = {}
   for ip, count in pairs(counts) do
      for trace, info in pairs(traces) do
         if ip >= info.mcode and ip <= info.mcode+info.szmcode then
            local key
            if info.mcloop > 0 and ip >= info.mcode + info.mcloop then
               key = tostring(trace)..":LOOP"
            else
               key = tostring(trace)
            end
            results[key] = (results[key] or 0) + count
            break
         end
      end
   end
   -- Sort from most to least samples.
   local order = {}
   for trace in pairs(results) do
      table.insert(order, trace)
   end
   table.sort(order, function(a,b) return results[a] > results[b] end)
   for _, trace in pairs(order) do
      local tracenr = tonumber(string.match(trace, "^%d+")) -- 123
      local traceinfo = string.match(trace, ":.*") or ""    -- ":LOOP"
      local info = traces[tracenr]
      -- % of samples
      local pct = results[trace]*100/nsamples
      -- parent: show where side-traces originate (trace/exit)
      local parent = ""
      if info.otr and info.oex then
         parent = "("..info.otr.."/"..info.oex..")"
      end
      -- link: show where the end of the trace branches to
      local lnk = ""
      local link, ltype = info.link, info.linktype
      if     link == tracenr or link == 0 then lnk = "->"..ltype
      elseif ltype == "root"              then lnk = "->"..link
      else                                     lnk = "->"..link.." "..ltype end
      -- Show the source location where the trace starts
      local loc = ""
      if info.func then
         local fi = jutil.funcinfo(info.func, info.pc)
         if fi.loc then loc = fi.loc end
      end
      local line = ("%3d%% TRACE %3d%-5s %-8s %s"):format(
         pct, tracenr, traceinfo, parent, loc)
      if pct >= 1 then
         print(line)
      end
   end
end

function selftest ()
   local max, interval = 1000, 1000
   start(max, interval)
   for i = 1, 1e8 do 
      for i = 1, 10 do end 
   end
   stop()
end

