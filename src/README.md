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
(`/var/run/snabb/<pid>`) and accessed with the equivalent of POSIX shared
memory (`shm_overview(7)`).

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

— Function **lib.files_in_directory** *directory*

Returns an array of filenames in *directory*.

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

— Function **lib.hexundump** *hexstring*

Returns byte string for *hexstring*.

— Function **lib.comma_value** *n*

Returns a string for decimal number *n* with magnitudes separated by
commas. Example:

```
comma_value(1000000) => "1,000,000"
```

— Function **lib.random_data** *length*

Returns a string of *length* bytes of random data.

— Function **lib.bounds_checked** *type*, *base*, *offset*, *size*

Returns a table that acts as a bounds checked wrapper around a C array of
*type* and *size* starting at *base* plus *offset*. *Type* must be a
ctype and the caller must ensure that the allocated memory region at
*base*/*offset* is at least `sizeof(type)*size` bytes long.

— Function **lib.timer** *duration*, *mode*, *timefun*

Returns a closure that will return `false` until *duration* has elapsed. If
*mode* is `'repeating'` the timer will reset itself after returning `true`,
thus implementing an interval timer. *Timefun* is used to get a monotonic time.
*Timefun* defaults to `C.get_time_ns`.

The “deadline” for a given *duration* is computed by adding *duration* to the
result of calling *timefun*, and is saved in the resulting closure. A
*duration* has elapsed when its deadline is less than or equal the value
obtained using *timefun* when calling the closure.


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
