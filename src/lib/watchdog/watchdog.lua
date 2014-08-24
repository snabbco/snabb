module(...,package.seeall)

ffi = require("ffi")
C   = ffi.C

-- Watchdog timeout in unit defined by `precision' (just below).
timeout = nil

-- Watchdog precision.
precision = nil

-- Set watchdog timeout to mseconds (milliseconds). Does NOT start the
-- watchdog. Values for mseconds>1000 are truncated to the next second,
-- e.g. set(1100) <=> set(2000).
function set (mseconds)
   if mseconds > 1000 then
      timeout = math.ceil(mseconds / 1000)
      precision = "second"
   else
      timeout = mseconds * 1000
      precision = "microsecond"
   end
end

-- (Re)set timeout. E.g. starts the watchdog if it has not been started
-- before and resets the timeout otherwise.
function reset ()
   if precision == "second" then
      C.alarm(timeout)
   elseif precision == "microsecond" then
      C.ualarm(timeout, 0)
   else
      error("Watchdog was not set.")
   end
end

-- Disable timeout.
function stop ()
   if precision == "second" then
      C.alarm(0)
   elseif precision == "microsecond" then
      C.ualarm(0,0)
   end
end
