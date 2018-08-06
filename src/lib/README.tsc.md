### Time Stamp Counter (lib.tsc)

A Time Stamp Counter (TSC) is an unsigned 64-bit value which increases
at a fixed frequency.  The latter property provides a measure of the
time that has passed between two readings of the counter in units of
clock ticks.

To convert a value in clock ticks to the corresponding number of
seconds requires a measurement of the actual frequency at which the
TSC runs.  This is referred to as calibration.  The `tsc` module
provides a uniform interface to TSCs based on different time sources.

Example usage
```lua
local tsc = require('lib.tsc')
local sleep = require("ffi").C.sleep
local function wait(t)
   print("source " .. t:source())
   local s1 = t:stamp()
   sleep(1)
   local s2 = t:stamp()
   print(("clock ticks %s, nanoseconds %s"):format(tostring(s2 - s1),
                 tostring(t:to_ns(s2 - s1))))
end

wait(tsc.new())
-- Override default
tsc.default_source = 'system'
wait(tsc.new())
```

#### Parameters

Parameters can be set by

```lua
local tsc = require('lib.tsc')
tsc.<parameter> = <value>
```

— Parameter **default_source** *source*

The time source used by a new TSC instance if no **source** key is
specified.  The default is `rdtsc`.

#### Functions

— Function **new** *config*

Create a new TSC instance.  The optional *config* argument is a table
with the following keys.

— Key **source**

*Optional*.  The name of the timing source to be used with this
instance. The following sources are available.  The default is `rdtsc`
(or whatever has been set by the `default_source` parameter).

 * `system`

   This source uses `clock_gettime(2)` with `CLOCK_MONOTONIC` provided
   by `ffi.C.get_time_ns()`.  The frequency is exactly 1e9 Hz,
   i.e. one tick per nanosecond.

 * `rdtsc`

   This source uses the [TSC](https://en.wikipedia.org/wiki/Time_Stamp_Counter) CPU
   register via the `rdtsc` instruction, provided that the platform
   supports the `constant_tsc` and `nonstop_tsc` features.  If these
   features are not present, a warning is printed and the TSC falls
   back to the `system` time source.

   The TSC register is consistent for all cores of a CPU.  However,
   the calling program is responsible for setting the CPU affinity on
   multi-socket systems.

   The `system` time source is used for calibration.

— Function **rdtsc**

Returns the current value of the CPU's TSC register through the
`rdtsc` instruction as a `uint64_t` object.

#### Methods

The object returned by the **new** function provides the following
methods.

— Method **tsc:source**

Returns the name of the time source, i.e. `rdtsc` or `system`.

— Method **tsc:time_fn**

Returns the function used to generate a time stamp for the configured
time source, which returns the value of the TSC as a `uint64_t`
object.

— Method **tsc:stamp**

Returns the current value of the TSC as a `uint64_t`.  It is
equivalent to the call `tsc:time_fn()()`.

— Method **tsc:tps**

Returns the number of clock ticks per second as a `uint64_t`.

— Method **tsc:to_ns**, *ticks*

Returns *ticks* converted from clock ticks to nanoseconds as a
`uint64_t`.  This method should be avoided in low-latency code paths
due to conversions from/to Lua numbers.
