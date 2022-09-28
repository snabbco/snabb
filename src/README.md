# Introduction

*Snabb* is an extensible, virtualized, Ethernet networking
toolkit.  With Snabb you can implement networking applications
using the *Lua language*. Snabb includes all the tools you need to
quickly realize your network designs and its really fast too!
Furthermore, Snabb is extensible and encourages you to grow the
ecosystem to match your requirements.

    DIAGRAM: Architecture
            +---------------------+
            | Your Network Design |
            +----*-----*-----*----+
                 |     |     |
    
    (Built in and custom Apps and Libraries)
    
                 |     |     |
           +-----*-----*-----*-----+
           |      Snabb Core       |
           +-----------------------+

The Snabb Core forms a runtime environment (*engine*) which
executes your *design*. A design is simply a Lua script used to drive the
Snabb stack, you can think of it as your top-level "main" routine.

In order to add functionality to the Snabb stack you can load
modules into the Snabb engine. These can be Lua modules as well as
native code objects. We differentiate between two classes of modules,
namely libraries and *Apps*. Libraries are simple collections of program
utilities to be used in your designs, apps or other libraries, just as
you might expect. Apps, on the other hand, are code objects that
implement a specific interface, which is used by the Snabb engine
to organize an *App Network*.

    DIAGRAM: Network
                   +---------+
                   |         |
                +->* Filter0 *--+
                |  |         |  |
                |  +---------+  |
    +---+----+  |               |  +----+---+
    |        *--+               +->*        |
    |  NIC0  |                     |  NIC1  |
    |        *<-+               +--*        |
    +---+----+  |               |  +----+---+
                |  +---------+  |
                |  |         |  |
                +--* Filter1 *<-+
                   |         |
                   +---------+

Usually, a Snabb design will create a series of apps, interconnect
these in a desired way using *links* and finally pass the resulting app
network on to the Snabb engine. The engine's job is to:

 * Pump traffic through the app network
 * Apply, and inform apps of configuration and link changes
 * Report on the network status


# Snabb API

The core modules defined below  can be loaded using Lua's `require`. For
example:

```
local config = require("core.config")

local c = config.new()
...
```

## App

An *app* is an isolated implementation of a specific networking
function. For example, a switch, a router, or a packet filter.

Apps receive packets on *input ports*, perform some processing, and
transmit packets on *output ports*. Each app has zero or more input and
output ports. For example, a packet filter may have one input and one
output port, while a packet recorder may have only an input port. Every
app must implement the interface below. Methods which may be left
unimplemented are marked as "optional".

— Method **myapp:new** *arg*

*Required*. Create an instance of the app with a given argument *arg*.
`Myapp:new` must return an instance of the app. The handling of *arg* is
up to the app but it is encouraged to use `core.config`'s `parse_app_arg`
to parse *arg*.


— Field **myapp.input**

— Field **myapp.output**

Tables of named input and output links.  These tables are initialized by
the engine for use in processing and are *read-only*.


— Field **myapp.appname**

Name of the app. *Read-only*.


— Field **myapp.shm**

Can be set to a specification for `core.shm.create_frame`. When set, this field
will be initialized to a frame of shared memory objects by the engine.


— Field **myapp.config**

Can be set to a specification for `core.lib.parse`. When set, the specification
will be used to validate the app’s arg when it is configured using
`config.app`.


— Method **myapp:link** *dir* *name*

*Optional*. Called during `engine.configure()` when a link of the app is
added. Unless `unlink` is specified this method is also called when a link
is removed.
Guaranteed to be called before `pull` and `push` are called with new links. 

*Dir* is either `'input'` or `'output'`, and *name* is the string name
of the link. I.e., the added link can be accessed at `self[dir][name]`.


— Method **myapp:unlink** *dir* *name*

*Optional*. Called during `engine.configure()` when a link of the app is
removed.

*Dir* is either `'input'` or `'output'`, and *name* is the string name
of the link.


— Method **myapp:pull**

*Optional*. Pull packets into the network.

For example: Pull packets from a network adapter into the app network by
transmitting them to output ports.


— Method **myapp:push**

*Optional*. Push packets through the system.

For example: Move packets from input ports to output ports or to a
network adapter.

— Field **myapp.push_link**

*Optional*. When specified must be a table of per-link `push()` methods
that take an input link as an argument. For example an app could specify
a **push_link** method for its input link *foo*:

```
Myapp = { push_link={} }
function Myapp.push_link:foo (input)
  while not link.empty(input) do something() end
end
```

**Push_link** methods are copied to a fresh table when the app is started,
and it is valid to create **push_link** methods dynamically during `link()`,
for example like so:

```
Myapp = { push_link={} }
function Myapp:link (dir, name)
  -- NB: Myapp.push_link ~= self.push_link
  if dir == 'input' then
    self.push_link[name] = function (self, input)
      while not link.empty(input) do something() end
    end
  end
end
function Myapp:unlink (dir, name)
  if dir == 'input' then
    self.push_link[name] = nil
  end
end
```

**Push** is not called when an app has **push_link** methods
for *all* of its input links. If, however, an app at least one input link
without an associated **push_link** method then **push** is called
in addition to the **push_link** methods.


— Method **myapp:tick**

*Optional*. Called periodically at **engine.tick_Hz** frequency.

For example: Move packets from input ports to output ports or to a
network adapter.


— Method **myapp:reconfig** *arg*

*Optional*. Reconfigure the app with a new *arg*. If this method is not
implemented the app instance is discarded and a new instance is created.


— Method **myapp:report**

*Optional*. Print a report of the current app status.


— Method **myapp:stop**

*Optional*. Stop the app and release associated external resources.


— Field **myapp.zone**

*Optional*. Name of the LuaJIT *profiling zone* used for this app
(descriptive string). The default is the module name.



## Config (core.config)

A *config* is a description of a packet-processing network. The network
is a directed graph. Nodes in the graph are *apps* that each process
packets in a specific way. Each app has a set of named input and output
*ports*—often called *rx* and *tx*. Edges of the graph are unidirectional
*links* that carry packets from an output port to an input port.

The config is a purely passive data structure. Creating and
manipulating a config object does not immediately affect operation.
The config has to be activated using `engine.configure`.

— Function **config.new**

Creates and returns a new empty configuration.


— Function **config.app** *config*, *name*, *class*, *arg*

Adds an app of *class* with *arg* to the *config* where it will be
assigned to *name*.

Example:

```
config.app(c, "nic", Intel82599, {pciaddr = "0000:00:00.0"})
```


— Function **config.link** *config*, *linkspec*

Add a link defined by *linkspec* to the config *config*. *Linkspec* must
be a string of the format

```
app_name1.output_port->app_name2.input_port
```

where `app_name1` and `app_name2` are names of apps in *config* and
`output_port` and `input_port` are valid output and input ports of the
referenced apps respectively.

Example:

```
config.link(c, "nic1.tx->nic2.rx")
```



## Engine (core.app)

The *engine* executes a config by initializing apps, creating links, and
driving the flow of execution. The engine also performs profiling and
reporting functions. It can be reconfigured during runtime. Within Snabb
Switch scripts the `core.app` module is bound to the global `engine`
variable.

— Function **engine.configure** *config*

Configure the engine to use a new config *config*. You can safely call
this method many times to incrementally update the running app
network. The engine updates the app network as follows:

 * Apps that did not exist in the old configuration are started.
 * Apps that do not exist in the new configuration are stopped. (The app `stop()` method is called if defined.)
 * Apps with unchanged configurations are preserved.
 * Apps with changed configurations are updated by calling their `reconfig()` method. If the `reconfig()` method is not implemented then the old instance is stopped a new one started.
 * Links with unchanged endpoints are preserved.

— Function **engine.main** *options*

Run the Snabb engine. *Options* is a table of key/value pairs. The
following keys are recognized:

 * `duration` - Duration in seconds to run the engine for (as a floating
   point number). If this is set you cannot supply `done`.
 * `done` - A function to be called repeatedly by `engine.main` until it
   returns `true`. Once it returns `true` the engine will be stopped and
   `engine.main` will return. If this is set you cannot supply
   `duration`.
 * `report` - A table which configures the report printed before
   `engine.main()` returns. The keys `showlinks` and `showapps` can be
   set to boolean values to force or suppress link and app reporting
   individually. By default `engine.main()' will report on links but not
   on apps.
 * `measure_latency` - By default, the `breathe()` loop is instrumented
   to record the latency distribution of running the app graph.  This
   information can be processed by the `snabb top` program.  Passing
   `measure_latency=false` in the *options* will disable this
   instrumentation.
 * `no_report` - A boolean value. If `true` no final report will be
   printed.


— Function **engine.stop**

Stop all apps in the engine by loading an empty configuration.

— Function **engine.now**

Returns monotonic time in seconds as a floating point number. Suitable
for timers.

— Variable **engine.busywait**

If set to true then the engine polls continuously for new packets to
process. This consumes 100% CPU and makes processing latency less
vulnerable to kernel scheduling behavior which can cause pauses of
more than one millisecond.

Default: false

— Variable **engine.Hz**

Frequency at which to poll for new input packets. The default value is
'false' which means to adjust dynamically up to 100us during low
traffic. The value can be overridden with a constant integer saying
how many times per second to poll.

This setting is not used when engine.busywait is true.

— Variable **engine.tick_Hz**

Frequency at which to call **app:tick** methods. The default value is
1000 (call `tick()`s every millisecond).

A value of 0 effectively disables `tick()` methods.

## Link (core.link)

A *link* is a [ring buffer](http://en.wikipedia.org/wiki/Circular_buffer)
used to store packets between apps. Links can be treated either like
arrays—accessing their internal structure directly—or as streams of
packets by using their API functions.

— Function **link.empty** *link*

Predicate used to test if a link is empty. Returns true if *link* is
empty and false otherwise.


— Function **link.full** *link*

Predicate used to test if a link is full. Returns true if *link* is full
and false otherwise.


— Function **link.nreadable** *link*

Returns the number of packets on *link*.


— Function **link.nwriteable** *link*

Returns the remaining number of packets that fit onto *link*.


— Function **link.receive** *link*

Returns the next available packet (and advances the read cursor) on
*link*. If the link is empty an error is signaled.


— Function **link.front** *link*

Return the next available packet without advancing the read cursor on
*link*. If the link is empty, `nil` is returned.


— Function **link.transmit** *link*, *packet*

Transmits *packet* onto *link*. If the link is full *packet* is dropped
(and the drop counter increased).


— Function **link.stats** *link*

Returns a structure holding ring statistics for the *link*:

 * `txbytes`, `rxbytes`: Counts of transferred bytes.
 * `txpackets`, `rxpackets`: Counts of transferred packets.
 * `txdrop`: Count of packets dropped due to ring overflow.


## Packet (core.packet)

A *packet* is an FFI object of type `struct packet` representing a network
packet that is currently being processed. The packet is used to explicitly
manage the life cycle of the packet. Packets are explicitly allocated and freed
by using `packet.allocate` and `packet.free`. When a packet is received using
`link.receive` its ownership is acquired by the calling app. The app must then
ensure to either transfer the packet ownership to another app by calling
`link.transmit` on the packet or free the packet using `packet.free`. Apps may
only use packets they own, e.g. packets that have not been transmitted or
freed. The number of allocatable packets is limited by the size of the
underlying “freelist”, e.g. a pool of unused packet objects from and to which
packets are allocated and freed.

— Type **struct packet**

```
struct packet {
    uint16_t length;
    uint8_t  data[packet.max_payload];
};
```

— Constant **packet.max_payload**

The maximum payload length of a packet.

— Function **packet.allocate**

Returns a new empty packet. An an error is raised if there are no packets left
on the freelist. Initially the `length` of the allocated is 0, and its `data`
is uninitialized garbage.

— Function **packet.free** *packet*

Frees *packet* and puts in back onto the freelist.

— Function **packet.clone** *packet*

Returns an exact copy of *packet*.

— Function **packet.resize** *packet*, *length*

Sets the payload length of *packet*, truncating or extending its payload. In
the latter case the contents of the extended area at the end of the payload are
filled with zeros.

— Function **packet.append** *packet*, *pointer*, *length*

Appends *length* bytes starting at *pointer* to the end of *packet*. An
error is raised if there is not enough space in *packet* to accomodate
*length* additional bytes.

— Function **packet.prepend** *packet*, *pointer*, *length*

Prepends *length* bytes starting at *pointer* to the front of
*packet*, taking ownership of the packet and returning a new packet.
An error is raised if there is not enough space in *packet* to
accomodate *length* additional bytes.

— Function **packet.shiftleft** *packet*, *length*

Take ownership of *packet*, truncate it by *length* bytes from the
front, and return a new packet. *Length* must be less than or equal to
`length` of *packet*.

— Function **packet.shiftright** *packet*, *length*

Take ownership of *packet*, moves *packet* payload to the right by
*length* bytes, growing *packet* by *length*. Returns a new packet.
The sum of *length* and `length` of *packet* must be less than or
equal to `packet.max_payload`.

— Function **packet.from_pointer** *pointer*, *length*

Allocate packet and fill it with *length* bytes from *pointer*.

— Function **packet.from_string** *string*

Allocate packet and fill it with the contents of *string*.

— Function **packet.account_free** *packet*

Increment internal engine statistics (*frees*, *freebytes*, *freebits*) as if
*packet* were freed, but do not actually put it back onto the freelist.

This function is intended to be used by I/O apps in special cases that need
more finegrained control over packet freeing.

— Function **packet.free_internal** *packet*

Free *packet* and put it back onto the freelist, but do not increment internal
engine statistics (*frees*, *freebytes*, *freebits*).

See **packet.account_free**, **packet.free**.


## Memory (core.memory)

Snabb allocates special
[DMA](https://en.wikipedia.org/wiki/Direct_memory_access) memory that
can be accessed directly by network cards. The important
characteristic of DMA memory is being located in contiguous physical
memory at a stable address.

— Function **memory.dma_alloc** *bytes*, [*alignment*]

Returns a pointer to *bytes* of new DMA memory.

Optionally a specific *alignment* requirement can be provided (in
bytes). The default alignment is 128.

— Function **memory.virtual_to_physical** *pointer*

Returns the physical address (`uint64_t`) the DMA memory at *pointer*.

— Variable **memory.huge_page_size**

Size of a single huge page in bytes. Read-only.


## Shared Memory (core.shm)

This module facilitates creation and management of named shared memory objects.
Objects can be created using `shm.create` similar to `ffi.new`, except that
separate calls to `shm.open` for the same name will each return a new mapping
of the same shared memory. Different processes can share memory by mapping an
object with the same name (and type). Each process can map any object any
number of times.

Mappings are deleted on process termination or with an explicit `shm.unmap`.
Names are unlinked from objects that are no longer needed using `shm.unlink`.
Object memory is freed when the name is unlinked and all mappings have been
deleted.

Names can be fully qualified or abbreviated to be within the current process.
Here are examples of names and how they are resolved where `<pid>` is the PID
of this process:

- Local: `foo/bar` ⇒ `/var/run/snabb/<pid>/foo/bar`
- Fully qualified: `/1234/foo/bar` ⇒ `/var/run/snabb/1234/foo/bar`

Behind the scenes the objects are backed by files on ram disk
(`/var/run/snabb/<pid>`) and accessed with the equivalent of POSIX
shared memory (`shm_overview(7)`). The files are automatically removed
on shutdown unless the environment `SNABB_SHM_KEEP` is set. The
location `/var/run/snabb` can be overridden by the environment
variable `SNABB_SHM_ROOT`.

Shared memory objects are created world-readable for convenient access
by diagnostic tools. You can lock this down by setting
`SNABB_SHM_ROOT` to a path under a directory with appropriate
permissions.

The practical limit on the number of objects that can be mapped will depend on
the operating system limit for memory mappings. On Linux the default limit is
65,530 mappings:

```
$ sysctl vm.max_map_count vm.max_map_count = 65530
```

— Function **shm.create** *name*, *type*

Creates and maps a shared object of *type* into memory via a hierarchical
*name*. Returns a pointer to the mapped object.

— Function **shm.open** *name*, *type*, [*readonly*]

Maps an existing shared object of *type* into memory via a hierarchical *name*.
If *readonly* is non-nil the shared object is mapped in read-only mode.
*Readonly* defaults to nil. Fails if the shared object does not already exist.
Returns a pointer to the mapped object.

— Function **shm.alias** *new-path* *existing-path*

Create an alias (symbolic link) for an object.

— Function **shm.path** *name*

Returns the fully-qualified path for an object called *name*.

— Function **shm.exists** *name*

Returns a true value if shared object by *name* exists.

— Function **shm.unmap** *pointer*

Deletes the memory mapping for *pointer*.

— Function **shm.unlink** *path*

Unlinks the subtree of objects designated by *path* from the filesystem.

— Function **shm.children** *path*

Returns an array of objects in the directory designated by *path*.

— Function **shm.register** *type*, *module*

Registers an abstract shared memory object *type* implemented by *module* in
`shm.types`. *Module* must provide the following functions:

 - **create** *name*, ...
 - **open**, *name*

and can optionally provide the function:

 - **delete**, *name*

The *module*’s `type` variable must be bound to *type*. To register a new type
a module might invoke `shm.register` like so:

```
type = shm.register('mytype', getfenv())
-- Now the following holds true:
--   shm.types[type] == getfenv()
```

— Variable **shm.types**

A table that maps types to modules. See `shm.register`.

— Function **shm.create_frame** *path*, *specification*

Creates and returns a shared memory frame by *specification* under *path*. A
frame is a table of mapped—possibly abstract‑shared memory objects.
*Specification* must be of the form:

```
{ <name> = {<module>, ...},
  ... }
```

*Module* must implement an abstract type registered with `shm.register`, and is
followed by additional initialization arguments to its `create` function.
Example usage:

```
local counter = require("core.counter")
-- Create counters foo/bar/{dtime,rxpackets,txpackets}.counter
local f = shm.create_frame(
   "foo/bar",
   {dtime     = {counter, C.get_unix_time()},
    rxpackets = {counter},
    txpackets = {counter}})
counter.add(f.rxpackets)
counter.read(f.dtime)
```

— Function **shm.open_frame** *path*

Opens and returns the shared memory frame under *path* for reading.

— Function **shm.delete_frame** *frame*

Deletes/unmaps a shared memory *frame*. The *frame* directory is unlinked if
*frame* was created by `shm.create_frame`.


### Counter (core.counter)

Double-buffered shared memory counters. Counters are 64-bit unsigned values.
Registered with `core.shm` as type `counter`.

— Function **counter.create** *name*, [*initval*]

Creates and returns a `counter` by *name*, initialized to *initval*. *Initval*
defaults to 0.

— Function **counter.open** *name*

Opens and returns the counter by *name* for reading.

— Function **counter.delete** *name*

Deletes and unmaps the counter by *name*.

— Function **counter.commit**

Commits buffered counter values to public shared memory.

— Function **counter.set** *counter*, *value*

Sets *counter* to *value*.

— Function **counter.add** *counter*, [*value*]

Increments *counter* by *value*. *Value* defaults to 1.

— Function **counter.read** *counter*

Returns the value of *counter*.


### Histogram (core.histogram)

Shared memory histogram with logarithmic buckets. Registered with `core.shm` as
type `histogram`.

— Function **histogram.new** *min*, *max*

Returns a new `histogram`, with buckets covering the range from *min* to *max*.
The range between *min* and *max* will be divided logarithmically.

— Function **histogram.create** *name*, *min*, *max*

Creates and returns a `histogram` as in `histogram.new` by *name*. If the file
exists already, it will be cleared.

— Function **histogram.open** *name*

Opens and returns `histogram` by *name* for reading.

— Method **histogram:add** *measurement*

Adds *measurement* to *histogram*.

— Method **histogram:iterate** *prev*

When used as `for count, lo, hi in histogram:iterate()`, visits all buckets in
*histogram* in order from lowest to highest. *Count* is the number of samples
recorded in that bucket, and *lo* and *hi* are the lower and upper bounds of
the bucket. Note that *count* is an unsigned 64-bit integer; to get it as a Lua
number, use `tonumber`.

If *prev* is given, it should be a snapshot of the previous version of the
histogram. In that case, the *count* values will be returned as a difference
between their values in *histogram* and their values in *prev*.

— Method **histogram:snapshot** [*dest*]

Copies out the contents of *histogram* into the `histogram` *dest* and returns
*dest*. If *dest* is not given, the result will be a fresh `histogram`.

— Method **histogram:clear**

Clears the buckets of *histogram*.

— Method **histogram:wrap_thunk* *thunk*, *now*

Returns a closure that wraps *thunk*, measuring and recording the difference
between calls to *now* before and after *thunk* into *histogram*.

— Method **histogram:summarize* *prev*

Returns the approximate minimum, average, and maximum values recorded in
*histogram*.

If *prev* is given, it should be a snapshot of a previous version of the
histogram. In that case, this method returns the approximate minimum, average
and maximum values for the difference between *histogram* and *prev*.


## Lib (core.lib)

The `core.lib` module contains miscellaneous utilities.

— Function **lib.equal** *x*, *y*

Predicate to test if *x* and *y* are structurally similar (isomorphic).

— Function **lib.can_open** *filename*, *mode*

Predicate to test if file at *filename* can be successfully opened with
*mode*.

— Function **lib.can_read** *filename*

Predicate to test if file at *filename* can be successfully opened for
reading.

— Function **lib.can_write** *filename*

Predicate to test if file at *filename* can be successfully opened for
writing.

— Function **lib.readcmd** *command*, *what*

Runs Unix shell *command* and returns *what* of its output. *What* must
be a valid argument to `file:read`.

— Function **lib.readfile** *filename*, *what*

Reads and returns *what* from file at *filename*. *What* must be a valid
argument to `file:read`.

— Function **lib.writefile** *filename*, *value*

Writes *value* to file at *filename* using `file:write`. Returns the
value returned by `file:write`.

— Function **lib.readlink** *filename*

Returns the true name of symbolic link at *filename*.

— Function **lib.dirname** *filename*

Returns the `dirname(3)` of *filename*.

— Function **lib.basename** *filename*

Returns the `basename(3)` of *filename*.

— Function **lib.firstfile** *directory*

Returns the filename of the first file in *directory*.

— Function **lib.firstline** *filename*

Returns the first line of file at *filename* as a string.

— Function **lib.load_string** *string*

Evaluates and returns the value of the Lua expression in *string*.

— Function **lib.load_conf** *filename*

Evaluates and returns the value of the Lua expression in file at
*filename*.

— Function **lib.store_conf** *filename*, *value*

Writes *value* to file at *filename* as a Lua expression. Supports
tables, strings and everything that can be readably printed using
`print`.

— Function **lib.bits** *bitset*, *basevalue*

Returns a bitmask using the values of *bitset* as indexes. The keys of
*bitset* are ignored (and can be used as comments).

Example:

```
bits({RESET=0,ENABLE=4}, 123) => 1<<0 | 1<<4 | 123
```

— Function **lib.bitset** *value*, *n*

Predicate to test if bit number *n* of *value* is set.

— Function **lib.bitfield** *size*, *struct*, *member*, *offset*,
*nbits*, *value*

Combined accesor and setter function for bit ranges of integers in cdata
structs. Sets *nbits* (number of bits) starting from *offset* to
*value*. If *value* is not given the current value is returned.

*Size* may be one of 8, 16 or 32 depending on the bit size of the integer
being set or read.

*Struct* must be a pointer to a cdata object and *member* must be the
literal name of a member of *struct*.

Example:

```
local struct_t = ffi.typeof[[struct { uint16_t flags; }]]
-- Assuming `s' is an instance of `struct_t', set bits 4-7 to 0xF:
lib.bitfield(16, s, 'flags', 4, 4, 0xf)
-- Get the value:
lib.bitfield(16, s, 'flags', 4, 4) -- => 0xF
```

— Function **string:split** *pattern*

Returns an iterator over the string split by *pattern*. *Pattern* must be
a valid argument to `string:gmatch`.

Example:

```
for word, sep in ("foo!bar!baz"):split("(!)") do
    print(word, sep)
end

> foo	!
> bar	!
> baz	nil
```

— Function **lib.hexdump** *string*

Returns hexadecimal string for bytes in *string*.

— Function **lib.hexundump** *hexstring*, *n*, *error* 

Returns string of *n* bytes for *hexstring*. Throws an error if less than *n*
hex-encoded bytes could be parsed unless *error* is `false`.

*Error* is optional and can be the error message to throw.

— Function **lib.comma_value** *n*

Returns a string for decimal number *n* with magnitudes separated by
commas. Example:

```
comma_value(1000000) => "1,000,000"
```

— Function **lib.random_bytes_from_dev_urandom** *length*

Return *length* bytes of random data, as a byte array, taken from
`/dev/urandom`.  Suitable for cryptographic usage.

— Function **lib.random_bytes_from_math_random** *length*

Return *length* bytes of random data, as a byte array, where each byte
was taken from `math.random(0, 255)`.  *Not* suitable for cryptographic
usage.

— Function **lib.random_bytes** *length*
— Function **lib.randomseed** *seed*

Initialize Snabb's random number generation facility.  If *seed* is nil,
then the Lua `math.random()` function will be seeded from
`/dev/urandom`, and `lib.random_bytes` will be initialized to
`lib.random_bytes_from_dev_urandom`.  This is Snabb's default mode of
operation.

Sometimes it's useful to make Snabb use deterministic random numbers.
In that case, pass a seed to **lib.randomseed**; Snabb will set
`lib.random_bytes` to `lib.random_bytes_from_math_random`, and also
print out a message to stderr indicating that we are using lower-quality
deterministic random numbers.

As part of its initialization process, Snabb will call `lib.randomseed`
with the value of the `SNABB_RANDOM_SEED` environment variable (if
any).  Set this environment variable to enable deterministic random
numbers.

— Function **lib.bounds_checked** *type*, *base*, *offset*, *size*

Returns a table that acts as a bounds checked wrapper around a C array of
*type* and *size* starting at *base* plus *offset*. *Type* must be a
ctype and the caller must ensure that the allocated memory region at
*base*/*offset* is at least `sizeof(type)*size` bytes long.

— Function **lib.throttle** *seconds*

Return a closure that returns `true` at most once during any *seconds*
(a floating point value) time interval, otherwise false.

— Function **lib.timeout** *seconds*

Returns a closure that returns `true` if *seconds* (a floating point
value) have elapsed since it was created, otherwise false.

— Function **lib.waitfor** *condition*

Blocks until the function *condition* returns a true value.

— Function **lib.waitfor2** *name*, *condition*, *attempts*, *interval*

Repeatedly calls the function *condition* in *interval*
(milliseconds). If *condition* returns a true value `waitfor2`
returns. If *condition* does not return a true value after *attempts*
`waitfor2` raises an error identified by *name*.

— Function **lib.yesno** *flag*

Returns the string `"yes"` if *flag* is a true value and `"no"`
otherwise.

— Function **lib.align** *value*, *size*

Return the next integer that is a multiple of *size* starting from
*value*.

— Function **lib.csum** *pointer*, *length*

Computes and returns the "IP checksum" *length* bytes starting at
*pointer*.

— Function **lib.update_csum** *pointer*, *length*, *checksum*

Returns *checksum* updated by *length* bytes starting at
*pointer*. The default of *checksum* is `0LL`.

— Function **lib.finish_csum** *checksum*

Returns the finalized *checksum*.

— Function **lib.malloc** *etype*

Returns a pointer to newly allocated DMA memory for *etype*.

— Function **lib.deepcopy** *object*

Returns a copy of *object*. Supports tables as well as ctypes.

— Function **lib.array_copy** *array*

Returns a copy of *array*. *Array* must not be a "sparse array".

— Function **lib.htonl** *n*

— Function **lib.htons** *n*

Host to network byte order conversion functions for 32 and 16 bit
integers *n* respectively. Unsigned.

— Function **lib.ntohl** *n*

— Function **lib.ntohs** *n*

Network to host byte order conversion functions for 32 and 16 bit
integers *n* respectively. Unsigned.

— Function **lib.random_bytes** *count*

Return a fresh array of *count* random bytes.  Suitable for
cryptographic usage.

— Function **lib.parse** *arg*, *config*

Validates *arg* against the specification in *config*, and returns a fresh
table containing the parameters in *arg* and any omitted optional parameters
with their default values. Given *arg*, a table of parameters or `nil`, assert
that from *config* all of the required keys are present, fill in any missing
values for optional keys, and error if any unknown keys are found. *Config* has
the following format:

```
config := { key = {[required=boolean], [default=value]}, ... }
```

Each key is optional unless `required` is set to a true value, and its default
value defaults to `nil`.

Example:

```
lib.parse({foo=42, bar=43}, {foo={required=true}, bar={}, baz={default=44}})
  => {foo=42, bar=43, baz=44}
```

- Function **lib.set** *vargs*

Reads a variable number of arguments and returns a table representing a set.
The returned value can be used to query whether an element belongs or not to
the set.

Example:

```
local t = set('foo', 'bar')
t['foo']  -- yields true.
t['quax'] -- yields false.
```

## Multiprocess operation (core.worker)

Snabb can operate as a _group_ of cooperating processes. The _main_
process is the initial one that you start directly. The optional
_worker_ processes are children spawned when the main process calls
the `core.worker` module.

    DIAGRAM: Multiprocessing
                  +----------+
          +-------+   Main   +-------+
          |       +----------+       |
          :            :             :
    +-----+----+  +----+-----+  +----+-----+
    | worker 1 |  :   ....   |  | worker N |
    +----------+  +----------+  +----------+

Each worker is a complete Snabb process. They can define app networks,
run the engine, and do everything else that ordinary Snabb processes
do. The exact behavior of each worker is determined by a Lua
expression provided upon creation.

Groups of Snabb processes each have the following special properties:

- **Group termination**: Terminating the main process automatically terminates all of the
  workers. This works for all process termination scenarios including
  `kill -9`.
- **Shared DMA memory**: DMA memory pointers obtained with `memory.dma_alloc()` are usable by
  all processes in the group. This means that you can share DMA memory
  pointers between processes, for example via `shm` shared memory
  objects, and reference them from any process. (The memory is
  automatically mapped at the expected address via a `SEGV` signal
  handler.)
- **PCI device shutdown**: For each PCI device opened by a process within the group, bus
  mastering (DMA) is disabled upon termination before any DMA memory
  is returned to the kernel. This prevents "dangling" DMA requests
  from corrupting memory that has been freed and reused.
  See [lib.hardware.pci](#pci-lib.hardware.pci) for details.

The `core.worker` API functions are available in the main process only:

— Function **worker.start** *name* *luacode*

Start a named worker process. The worker starts with a completely
fresh Snabb process image (`fork()+execve()`) and then executes the
string *luacode* as a Lua source code expression.

Example:

```
worker.start("myworker", [[
   print("hello world, from a Snabb worker process!")
   print("could configure and run the engine now...")
]])
```

— Function **worker.stop** *name*

Stop a named worker process. The worker is abruptly killed.

Example:

```
worker.stop("myworker")
```

— Function **worker.status**

Return a table summarizing the status of all workers. The table key is
the worker name and the value is a table with `pid` and `alive`
attributes.

Example:

```
for w, s in pairs(worker.status()) do
   print(("  worker %s: pid=%s alive=%s"):format(
         w, s.pid, s.alive))
end
```

Output:

```
worker w3: pid=21949 alive=true
worker w1: pid=21947 alive=true
worker w2: pid=21948 alive=true
```

## Main

Snabb designs can be run either with:

    snabb <snabb-arg>* <design> <design-arg>*

or

    #!/usr/bin/env snabb <snabb-arg>*
    ...

The *main* module provides an interface for running Snabb scripts.
It exposes various operating system functions to scripts.

— Field **main.parameters**

A list of command-line arguments to the running script. Read-only.


— Function **main.exit** *status*

Cleanly exits the process with *status*.
