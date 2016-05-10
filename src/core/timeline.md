### Timeline

The timeline is a high-resolution event log that stores entries in a
shared-memory ring buffer. Log entries are timestamped with
cycle-precise wall-clock time based on the CPU [Time Stamp Counter
(TSC)](https://en.wikipedia.org/wiki/Time_Stamp_Counter). Each log
message references predefined strings for its category and
format-string and stores up to four 64-bit argument values.

Timeline messages can be dynamically enabled or disabled based on
their priority. This supports periodically enabling detailed trace
messages for short periods of time (e.g. 100 microseconds) to ensure
that the log always includes a sample of interesting data for
analysis.

Logging to the timeline is efficient. Logging costs around 50 cycles
when a message is enabled and around 5 cycles when disabled. The
logging function is written in assembly language and is called by
LuaJIT via the FFI. (Checking whether log messages are enabled is
invisible to the trace compiler because it is done in the FFI call.)

#### File format and binary representation

The binary representation has three components:

- header: magic number, file format version, flags.
- entries: array of 64-byte log entries.
- stringtable: string constants (to referenced by their byte-index)

```
    DIAGRAM: Timeline
    +-------------------------+
    |      header (64B)       |
    +-------------------------+
    |                         |
    |                         |
    |     entries (~10MB)     |
    |                         |
    |                         |
    +-------------------------+
    |   stringtable (~1MB)    |
    +-------------------------+
```

The timeline can be read by scanning through the entries and detecting
the first and last entries by comparing timestamps. The entries can be
converted from binary data to human-readable strings by using the
format strings that they reference.

#### Usage

Create a timeline as a shared memory object with default file size:

```
tl = timeline.new("/timeline")
```

Define an event that can be logged on this timeline:

```
local proc = timeline.define(tl, 'example', 'trace', "processed $tcp, $udp, and $other")
```

Log a series of events:

```
proc(10, 20, 3)
proc(50, 60, 8)
```

The log now contains these entries:

```
<TIMESTAMP> example    processed tcp(10), udp(20), and other(3)
<TIMESTAMP> example    processed tcp(50), udp(60), and other(8)
```

#### API

— Function **new** *shmpath* *[entries]* *[stringtablesize]*

Create a new timeline at the given shared memory path.

- *entries* defaults to 1024*1024 entries (64 megabytes). This could be increased if more events are needed. The value must be a power of 2.
- *stringtablesize* defaults to one megabyte. This is expected to be more than sufficient.

— Function **define** *timeline* *category* *priority* *message*

Defines a message that can be logged to this timeline. Returns a
function that is called to log the event.

- *category* is a short descriptive string like "luajit", "engine", "pci01:00.0".
- *priority* is one of the strings `error`, `warning`, `info`,
   `trace`, `app`, `packet`, `library`.
- *message* is text describing the event. This can be a one-liner or a
   detailed multiline description. Words on the first line starting
   with `$` define arguments to the logger function which will be
   stored as 64-bit values (maximum four per message).

The priority should be chosen according to how frequently events will
occur. This will make it possible for users to control how much detail
is included in the log, and how quickly it wraps around, by choosing a
suitable minimum event priority. Specifically choose `trace` for
occasional events, `app` for per-breath events, `packet` for
per-packet events, and `library` for events in library functions that
could potentially be called in a tight loop. (If none of these
priority names perfectly describes your use case then pick the one you
think best matches the frequency of your events.)

— Function **save** *timeline* *filename*

Save a snapshot of the timeline to a file. The file format is the raw binary timeline format.

— Function **priority** *timeline* *level*

Set the minimum priority that is required for a message to be logged
on the timeline. This can be used to control the rate at which
messages are logged to the timeline to manage processing overhead and
the rate of churn in the ring buffer.

The level can be the strings accepted by `define()` or one of the
strings `all` or `none`.

— Function **dump** *filename* *[maxentries]*

Print the contents of a timeline, ordered from newest to oldest.

This dump function is intended as a simple example. More sophisticated
log viewing and analysis tools are eagerly anticipated.

Here is the output:

```
numa core      -cycles category         message
0    4         5033652 selftest         invoked many events(1000000)
0    4         5013972 selftest         invoked many events(1000000)
0    4         5178340 selftest         invoked many events(1000000)
0    4      1753835508 selftest         timing tight loop of disabled events
0    4              60 selftest         event with no args
0    4              40 selftest         event with one arg: i(1048575)
0    4              40 selftest         event with four args: i(1048575), 2i(2097150), 3i(3145725), and 4i(4194300)
0    4              36 selftest         event with no args
0    4              40 selftest         event with one arg: i(1048574)
0    4              40 selftest         event with four args: i(1048574), 2i(2097148), 3i(3145722), and 4i(4194296)
0    4              36 selftest         event with no args
0    4              40 selftest         event with one arg: i(1048573)
0    4              40 selftest         event with four args: i(1048573), 2i(2097146), 3i(3145719), and 4i(4194292)
0    4              36 selftest         event with no args
0    4              40 selftest         event with one arg: i(1048572)
0    4              40 selftest         event with four args: i(1048572), 2i(2097144), 3i(3145716), and 4i(4194288)
```
