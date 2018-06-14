### Round-robin database (lib.rrd)

A *round-robin database* (RRD) is a time-limited store of historical
data.  The RRD library in Snabb allows users to store and query counter
change rates over time.

The RRD format is defined by the venerable `rrdtool` software package.
Snabb's RRD library is careful to be compatible with the standard RRD
format, so that we can use `rrdtool` to generate pretty graphs.

Before going to the API reference, first some concepts.  A round-robin
database is fed with raw readings, which can come at any time.  Data
storage starts by collecting these readings into evenly-spaced *primary
data points* (PDPs).  The sampling rate of these primary data points is
defined when you create the RRD.

Interestingly, RRD builds in the notion of "unknown data" throughout:
sometimes you just don't have data for the time range corresponding to a
particular PDP.  This is of course the case just after creating the RRD,
but it can also happen if a reading doesn't come in on time.  So, some
PDPs will be known and some others will be unknown.

An RRD can have multiple sources of data.  Again, this set of sources is
declared when the RRD is created.  There will be one logical stream of
primary data points per source.

Primary data points are just the start, however; the actual long-term
storage is made up of *consolidated data points* (CDPs).  A CDP is
constructed from one or more PDPs via a *consolidation function* (CF).
Snabb supports four consolidation functions: `average`, `min`,
`max`, and `last`.  Average takes the average of the PDPs within
range, min and max take the lowest or highest values
respectively, and last takes the last one.  An archive also specifies
its own parameters for how many unknown PDPs should cause the CDP to be
considered unknown as well.

You can defined multiple *archives* of CDPs in one RRD.  For example,
you can define one archive for the average incoming packet rate, and
another for the maximum incoming packet rate.  While all archives in a
RRD use the same data sources, they can have different consolidation
functions, different overall lengths, and different windows (numbers of
PDP used to create each CDP).

Finally, note that the overall time range associated with any archive is
limited.  If for example your RRD has PDPs sampled every 5 seconds, and
an archive configured to collect 6 PDPs per CDP, that would be 30
seconds per CDP; then if the archive is 600 CDPs long, then that archive
would only cover the last 30s/CDP * 600 CDP = 18000s or 300 minutes.
The CDPs are stored in an ever-advancing circular buffer that's updated
in round-robin fashion, with new data overwriting the oldest data; hence
the name RRD.

— Function **rrd.new** *parameters*

Create a new round-robin database.  *parameters* is a table of key/value
pairs.  The following keys are defined:

 * `base_interval`: The "base interval" of the RRD, indicating how often
   to expect primary data points to arrive.  The smaller the base
   interval, the more precise the information, but the higher the
   overhead.  Defaults to `1s`, indicating one second.  Other recognized
   suffixes include `m` for minutes, `h` for hours, `d` for days, `w`
   for weeks, `M` for months, or `y` for years.  If given as a number,
   assumed to be seconds.
 * `sources`: An array of source definitions (see below).  Required.
 * `archives`: An array of archive definitions (see below).  Required.

The sources define what data is being collected, and the archives define
how the data are consolidated and stored.

A source definition is a table of key/value pairs.  The following keys
are defined in a source definition:

 * `name`: The name of the data series, as a string.  Maximum 19
   characters.  Required.
 * `type`: The type of the data.  Either `counter` or `gauge`.  Counter
   data is appropriate for possibly-wrapping counter values.  Snabb will
   diff the previous `uint64_t` counter reading to the current one, and
   will store a per-second change rate as the primary data point.  Thus
   `counter` is a kind of derivative, which is usually what you want;
   e.g. you usually want to know how many packets per second the system
   was processing an hour ago, not the total number of processed
   packets.  However if what you want to know are historical levels, use
   `gauge` instead.  Note that gauge values are stored as
   double-precision floats.  The default is `counter`.
 * `interval`: How often data needs to arrive in order for the readings
   to be considered valid.  For example, if given as `1m`, then if the
   last reading was more than a minute ago, then the PDP for the current
   reading will be marked as unknown.
 * `min`, `max`: These set limits for the PDP values.  If the computed
   PDP is outside these limits, the PDP is marked as unknown.  Defaults
   to not-a-number, indicating no limit.

An archive definition is also a table of key/value pairs, with the
following keys defined:

 * `cf`: The consolidation function; either `average`, `min`,
   `max`, or `last`.  The default is `average`.  See the discussion
   above for more on consolidation functions.
 * `duration`: How much data to store, in terms of time.  Required.
   As with `base_interval`, can be expressed in terms of hours, weeks,
   and so on.  If given as a number, indicates seconds.
 * `interval`: How often to record a consolidated data point.  The
   smaller this number, the more precise the information, but the larger
   the file and the more overhead.
 * `min_coverage`: The minimum fraction of the set of PDPs that are
   consolidated into a corresponding CDP that must be known, for the CDP
   to be marked as known.  Defaults to `0.5`, indicating that at least
   half of corresponding PDPs must be marked as known.

— Function **rrd.create_file** *filename* *arg*

Create a new round-robin database as if calling `rrd.new` on *arg*, and
then arrange for it to be mapped directly to *filename*.  Any subsequent
update to the returned RRD database will be written to the file.

— Function **rrd.create_shm** *name* *arg*

Like **rrd.create_file**, but determining the file name by passing
*name* to the `resolve` function of `core.shm`.

— Function **rrd.open_mem** *ptr* *size* *filename*

Load a round-robin database from memory.  The database will be writable
if the memory is writable.  *filename* is optional.  *ptr* will be kept
alive as long as the RRD object is alive, which allows an FFI finalizer
to be attached to *ptr* to release associated resources like memory
mappings, if needed.

— Function **rrd.open_file** *filename* *writable*

Load a round-robin database from disk.  Updates to the file will be
directly reflected in the RRD object.  The file must exist already.
*writable* defaults to false.

— Function **rrd.open_shm** *name* *writable*

Like **rrd.open_file**, but determining the file name by passing
*name* to the `resolve` function of `core.shm`.

— Function **rrd.dump** *rrd* *stream*
— Method **rrd:dump** *stream*

Write a copy of *rrd* to *stream*.

— Function **rrd.dump_file** *rrd* *filename*
— Method **rrd:dump_file** *filename*

Write a copy of *rrd* to the file *filename*.  Any existing contents
will be overwritten.

— Function **rrd.now**

Return the current time, as a double, for the purposes of a RRD file.
RRD stores the last update time in the file, as expressed by the
`gettimeofday` system call.

— Function **rrd.isources** *rrd*
— Method **rrd:isources**

Return an iterator for the data sources defined in *rrd*, for use in
`for` statements.  Example:

```lua
for i, name, type, interval, min, max in rrd:isources() do
   print('sources['..i..']: '..name)
end
```

— Function **rrd.iarchives** *rrd*
— Method **rrd:iarchives**

Return an iterator for the archives defined in *rrd*, for use in `for`
statements.  Example:

```lua
for i, cf, row_count, pdp_per_cdp, coverage in rrd:iarchives() do
   print('archive '..i..' has '..pdp_per_cdp..' PDPs per CDP')
end
```

— Function **rrd.ref** *rrd* *t*
— Method **rrd:ref** *t*

Return the data points archived in *rrd* at time *t*.  If *t* is
negative, it is considered to be relative to the last time added to
*rrd*.

The return value is a table indexed by data source name, then by
consolidation function, then containing an array of readings.  (One time
may have a number of readings, e.g. for archives with the same CF but
different intervals.)

The results may be interpreted like this:

```lua
for name, source in pairs(rrd:ref(t)) do
   local type = source.type
   for cf, values in pairs(source.cf) do
      print('readings for '..name..'.. ('..cf..'/'..type..'):')
      for _,x in ipairs(values) do
         print(x.value..' (interval: '..x.interval..')')
      end
   end
end
```

— Function **rrd.add** *rrd* *values* *t*
— Method **rrd:add** *values* *t*

Add a reading to the round-robin database *rrd*.  If *t* is not given,
it defaults to `rrd.now()`.

*values* is a table where the keys are the data source names, and the
values are the corresponding raw values.  These values will be used to
form primary data points, which are then used to create consolidated
data points, which are then written into the archives.  See the intro
for full information.
