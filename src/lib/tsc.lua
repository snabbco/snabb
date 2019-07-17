-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Provide a time stamp counter suitable for measuring time intervals.

module(...,package.seeall)

local lib = require("core.lib")
local C   = require("ffi").C
require("core.lib_h")

default_source = 'rdtsc'
local calibration_interval = 5e8

-- Return the value of the CPU's TSC register
local rdtsc_code
rdtsc = require('dynasm').loadstring [[
   local ffi = require('ffi')
   local dasm = require('dasm')
   |.arch x64
   |.actionlist actions
   local Dst = dasm.new(actions)
   | rdtsc
   | shl rdx, 32
   | or rax, rdx
   | ret
   rdtsc_code = Dst:build()
   return ffi.cast('uint64_t (*)()', rdtsc_code)
]]()

local cpuinfo = lib.readfile("/proc/cpuinfo", "*a")
assert(cpuinfo, "failed to read /proc/cpuinfo for tsc check")
local have_usable_rdtsc = (cpuinfo:match("constant_tsc") and
                              cpuinfo:match("nonstop_tsc"))

local rdtsc_tps

local time_sources = {
   rdtsc = {
      time_fn = rdtsc,
      calibrate_fn = function ()
         if not rdtsc_tps then
            local start_ns = C.get_time_ns()
            local start_ticks = rdtsc()
            for _ = 1, calibration_interval do end
            local end_ticks = rdtsc()
            local end_ns = C.get_time_ns()
            rdtsc_tps = tonumber(end_ticks - start_ticks)/tonumber(end_ns - start_ns)
               * 1000000000 + 0ULL
         end
         return rdtsc_tps
      end
   },
   system = {
      time_fn = C.get_time_ns,
      calibrate_fn = function ()
         return 1000000000ULL
      end
   }
}

local tsc = {}

function new (arg)
   local config = lib.parse(arg, { source = { default = default_source } })
   local o = {}
   if config.source == 'rdtsc' and not have_usable_rdtsc then
      print("tsc: rdtsc is unusable on this system, "
               .. "falling back to system time source")
      config.source = 'system'
   end
   o._source = config.source

   local source = assert(time_sources[o._source],
                         "tsc: unknown time source '" .. o._source .."'")
   o._time_fn = source.time_fn
   -- Ticks per second (uint64)
   o._tps = source.calibrate_fn()
   -- Nanoseconds per tick (Lua number)
   o._nspt = 1/tonumber(o._tps) * 1000000000

   return setmetatable( o, { __index = tsc })
end

function tsc:source ()
   return self._source
end

function tsc:time_fn ()
   return self._time_fn
end

function tsc:stamp ()
   return self._time_fn()
end

function tsc:tps ()
   return self._tps
end

function tsc:to_ns (ticks)
   if self._source == 'system' then
      return ticks
   else
      return tonumber(ticks) * self._nspt + 0ULL
   end
end

function selftest()
   local function check(tsc)
      for _ = 1, 10 do
         local start_ns = C.get_time_ns()
         local start_tsc = tsc:stamp()
         for _ = 1, calibration_interval do end
         local end_ns = C.get_time_ns()
         local end_tsc = tsc:stamp()
         local diff_ns = tonumber(end_ns - start_ns)
         local diff_tsc = tonumber(tsc:to_ns(end_tsc) - tsc:to_ns(start_tsc))
         local diff = diff_ns - diff_tsc
         assert(math.abs(diff/diff_ns) < 1e-3, tsc:source())
      end
   end

   check(new({ source = 'rdtsc' }))
   check(new({ source = 'system' }))
end
