## Library routines

### PMU (CPU Performance Monitoring Unit) (lib.pmu)

This module counts and reports on CPU events such as cache misses,
branch mispredictions, utilization of internal CPU resources such
as execution units, and so on.

Hundreds of low-level counters are available. The exact list
depends on CPU model. See pmu_cpu.lua for our definitions.

API:

```
profile(fn[, event_list, aux]) => value [and print report]
  Execute 'fn' and print a measurement report for event_list.
  This is a simple convenience function over the API below.

measure(fn[, event_list]) => result, table {counter->value}
  Execute 'fn' and return the event counters as a second value.
  This is a convenience similar to profile().

is_available() => true | false, why
  Return true if hardware performance counters are available.
  Otherwise return false with a string briefly explaining why.

setup(event_list)
  Setup the hardware performance counters to track a given list of
  events (in addition to the built-in fixed-function counters).
  
  Each event is a Lua string pattern. This could be a full event name:
    'mem_load_uops_retired.l1_hit'
  or a more general pattern that matches several counters:
    'mem_load.*l._hit'

  Return the number of overflowed counters that could not be
  tracked due to hardware constraints. These will be the last
  counters in the list.

  Example:
    setup({"uops_issued.any",
           "uops_retired.all",
           "br_inst_retired.conditional",
           "br_misp_retired.all_branches"}) => 0

new_counter_set()
  Return a "counter_set" object that can be used for accumulating events.

  The counter_set will be valid only until the next call to setup().

switch_to(counter_set)
  Switch_To to a new set of counters to accumulate events in. Has the
  side-effect of committing the current accumulators to the
  previous record.

  If counter_set is nil then do not accumulate events.

to_table(counter_set) => table {eventname = count}
  Return a table containing the values accumulated in the counter set.

Example:
  to_table(cs) =>
    {
     -- Fixed-function counters
     instructions                 = 133973703,
     cycles                       = 663011188,
     ref-cycles                   = 664029720,
     -- General purpose counters selected with setup()
     uops_issued.any              = 106860997,
     uops_retired.all             = 106844204,
     br_inst_retired.conditional  =  26702830,
     br_misp_retired.all_branches =       419
    }

report(counter_set,  aux)
  Print a textual report on the values accumulated in a counter set.
  Optionally include auxiliary application-level counters. The
  ratio of each event to each auxiliary counter is also reported.

  Example:
    report(my_counter_set, {packet = 26700000, breath = 208593})
  prints output approximately like:
    EVENT                                   TOTAL     /packet     /breath
    instructions                      133,973,703       5.000     642.000
    cycles                            663,011,188      24.000    3178.000
    ref-cycles                        664,029,720      24.000    3183.000
    uops_issued.any                   106,860,997       4.000     512.000
    uops_retired.all                  106,844,204       4.000     512.000
    br_inst_retired.conditional        26,702,830       1.000     128.000
    br_misp_retired.all_branches              419       0.000       0.000
    packet                             26,700,000       1.000     128.000
    breath                                208,593       0.008       1.000
```

### Checksum calculation (lib.checksum)

```
This module exposes the interface:
  checksum.ipsum(pointer, length, initial) => checksum

pointer is a pointer to an array of data to be checksummed. initial
is an unsigned 16-bit number in host byte order which is used as
the starting value of the accumulator.  The result is the IP
checksum over the data in host byte order.

The initial argument can be used to verify a checksum or to
calculate the checksum in an incremental manner over chunks of
memory.  The synopsis to check whether the checksum over a block of
data is equal to a given value is the following

 if ipsum(pointer, length, value) == 0 then
   -- checksum correct
 else
   -- checksum incorrect
 end

To chain the calculation of checksums over multiple blocks of data
together to obtain the overall checksum, one needs to pass the
one's complement of the checksum of one block as initial value to
the call of ipsum() for the following block, e.g.

 local sum1 = ipsum(data1, length1, 0)
 local total_sum = ipsum(data2, length2, bit.bnot(sum1))

The actual implementation is chosen based on running CPU.
```

### Mac addresses (lib.macaddress)

```
 MAC address handling object.
depends on LuaJIT's 64-bit capabilities,
both for numbers and bit.* library
```

### JSON encode/decode (lib.json)

```
function decode(s, startPos):

Decodes a JSON string and returns the decoded value as a Lua data structure / value.

@param s The string to scan.
@param [startPos] Optional starting position where the JSON string is located. Defaults to 1.
@param Lua object, number The object that was scanned, as a Lua table / string / number / boolean or nil,
and the position of the first character after
the scanned JSON object.
```

## Specialized data structures


 filter (lib.bloom_filter)

```
Given the expected number of items n to be stored in the filter and
the maxium acceptable false-positive rate p when the filter
contains that number of items, the size m of the storage cell in
bits and the number k of hash calculations are determined by

 m = -n ln(p)/ln(2)^2
 k = m/n ln(2) = -ln(p)/ln(2)

According to
<http://www.eecs.harvard.edu/~kirsch/pubs/bbbf/esa06.pdf>, the k
independent hash functions can be replaced by two h1, h2 and the
"linear combinations" h[i] = h1 + i*h2 (i=1..k) without changing
the statistics of the filter.  Furthermore, h1 and h2 can be
derived from the same hash function using double hashing or seeded
hashing.  This implementation requires the "x64_128" variant of the
Murmur hash family provided by lib.hash.murmur.

Storing a sequence of bytes of length l in the filter proceeds as
follows.  First, the hash function is applied to the data with seed
value 0.

 h1 = hash(data, l, 0)

In this pseudo-code, h1 represents the lower 64 bits of the actual
hash.  The second hash is obtained by using h1 as seed

 h2 = hash(data, l, h1)

Finally, k values in the range [0, m-1] are calculated as

 k_i = (h1 + i*h2) % m

In order to be able to implement the mod m operation using bitops,
m is rounded up to the next power of 2.  In that case, the k_i can
be calculated efficiently by

 k_i = bit.band(h1 + i*h2, m-1)

The values k_i represent the original data.  Such a set of values
is called an *item*.  The actual filter consists of a data
structure that stores one bit for each of the m elements in the
filter, called a *cell*.  To store an item in a cell, the bits at
the positions given by the values k_i are set to one.
```

### Ctable (lib.ctable)

A *ctable* is a hash table whose keys and values are instances of FFI
data types.  In Lua parlance, an FFI value is a "cdata" value, hence the
name "ctable".

A ctable is parameterized for the specific types for its keys and
values.  This allows for the table to be stored in an efficient manner.
Adding an entry to a ctable will copy the value into the table.
Logically, the table "owns" the value.  Lookup can either return a
pointer to the value in the table, or copy the value into a
user-supplied buffer, depending on what is most convenient for the user.

As an implementation detail, the table is stored as an open-addressed
robin-hood hash table with linear probing.  This means that to look up a
key in the table, we take its hash value (using a user-supplied hash
function), map that hash value to an index into the table by scaling the
hash to the table size, and then scan forward in the table until we find
an entry whose hash value is greater than or equal to the hash in
question.  Each entry stores its hash value, and empty entries have a
hash of `0xFFFFFFFF`.  If the entry's hash matches and the entry's key
is equal to the one we are looking for, then we have our match.  If the
entry's hash is greater than our hash, then we have a failure.  Hash
collisions are possible as well of course; in that case we continue
scanning forward.

The distance travelled while scanning for the matching hash is known as
the *displacement*.  The table measures its maximum displacement, for a
number of purposes, but you might be interested to know that a maximum
displacement for a table with 2 million entries and a 40% load factor is
around 8 or 9.  Smaller tables will have smaller maximum displacements.

The ctable has two lookup interfaces.  One will perform the lookup as
described above, scanning through the hash table in place.  The other
will fetch all entries within the maximum displacement into a buffer,
then do a branchless binary search over that buffer.  This second
streaming lookup can also fetch entries for multiple keys in one go.
This can amortize the cost of a round-trip to RAM, in the case where you
expect to miss cache for every lookup.

To create a ctable, first create a parameters table specifying the key
and value types, along with any other options.  Then call `ctable.new`
on those parameters.  For example:

```lua
local ctable = require('lib.ctable')
local ffi = require('ffi')
local params = {
   key_type = ffi.typeof('uint32_t'),
   value_type = ffi.typeof('int32_t[6]'),
   hash_fn = ctable.hash_i32,
   max_occupancy_rate = 0.4,
   initial_size = math.ceil(occupancy / 0.4)
}
local ctab = ctable.new(params)
```

— Function **ctable.new** *parameters*

Create a new ctable.  *parameters* is a table of key/value pairs.  The
following keys are required:

 * `key_type`: An FFI type (LuaJIT "ctype") for keys in this table.
 * `value_type`: An FFI type (LuaJT "ctype") for values in this table.
 * `hash_fn`: A function that takes a key and returns a hash value.

Hash values are unsigned 32-bit integers in the range `[0,
0xFFFFFFFF)`.  That is to say, `0xFFFFFFFF` is the only unsigned 32-bit
integer that is not a valid hash value.  The `hash_fn` must return a
hash value in the correct range.

Optional entries that may be present in the *parameters* table include:

 * `initial_size`: The initial size of the hash table, including free
   space.  Defaults to 8 slots.
 * `max_occupancy_rate`: The maximum ratio of `occupancy/size`, where
   `occupancy` denotes the number of entries in the table, and `size` is
   the total table size including free entries.  Trying to add an entry
   to a "full" table will cause the table to grow in size by a factor of
   2.  Defaults to 0.9, for a 90% maximum occupancy ratio.
 * `min_occupancy_rate`: Minimum ratio of `occupancy/size`.  Removing an
   entry from an "empty" table will shrink the table.

#### Methods

Users interact with a ctable through methods.  In these method
descriptions, the object on the left-hand-side of the method invocation
should be a ctable.

— Method **:resize** *size*

Resize the ctable to have *size* total entries, including empty space.

— Method **:insert** *hash*, *key*, *value*, *updates_allowed*

An internal helper method that does the bulk of updates to hash table.
*hash* is the hash of *key*.  This method takes the hash as an explicit
parameter because it is used when resizing the table, and that way we
avoid calling the hash function in that case.  *key* and *value* are FFI
values for the key and the value, of course.

*updates_allowed* is an optional parameter.  If not present or false,
then the `:insert` method will raise an error if the *key* is already
present in the table.  If *updates_allowed* is the string `"required"`,
then an error will be raised if *key* is *not* already in the table.
Any other true value allows updates but does not require them.  An
update will replace the existing entry in the table.

Returns the index of the inserted entry.

— Method **:add** *key*, *value*, *updates_allowed*

Add an entry to the ctable, returning the index of the added entry.  See
the documentation for `:insert` for a description of the parameters.

— Method **:update** *key*, *value*

Update the entry in a ctable with the key *key* to have the new value
*value*.  Throw an error if *key* is not present in the table.

— Method **:lookup_ptr** *key*

Look up *key* in the table, and if found return a pointer to the entry.
Return nil if the value is not found.

An entry pointer has three fields: the `hash` value, which must not be
modified; the `key` itself; and the `value`.  Access them as usual in
Lua:

```lua
local ptr = ctab:lookup(key)
if ptr then print(ptr.value) end
```

Note that pointers are only valid until the next modification of a
table.

— Method **:lookup_and_copy** *key*, *entry*

Look up *key* in the table, and if found, copy that entry into *entry*
and return true.  Otherwise return false.

— Method **:remove_ptr** *entry*

Remove an entry from a ctable.  *entry* should be a pointer that points
into the table.  Note that pointers are only valid until the next
modification of a table.

— Method **:remove** *key*, *missing_allowed*

Remove an entry from a ctable, keyed by *key*.

Return true if we actually do find a value and remove it.  Otherwise if
no entry is found in the table and *missing_allowed* is true, then
return false.  Otherwise raise an error.

— Method **:selfcheck**

Run an expensive internal diagnostic to verify that the table's internal
invariants are fulfilled.

— Method **:dump**

Print out the entries in a table.  Can be expensive if the table is
large.

— Method **:iterate**

Return an iterator for use by `for in`.  For example:

```lua
for entry in ctab:iterate() do
   print(entry.key, entry.value)
end
```

#### Hash functions

Any hash function will do, as long as it produces values in the `[0,
0xFFFFFFFF)` range.  In practice we include some functions for hashing
byte sequences of some common small lengths.

— Function **ctable.hash_32** *number*

Hash a 32-bit integer.  As a `hash_fn` parameter, this will only work if
your key type's Lua representation is a Lua number.  For example, use
`hash_32` on `ffi.typeof('uint32_t')`, but use `hashv_32` on
`ffi.typeof('uint8_t[4]')`.

— Function **ctable.hashv_32** *ptr*

Hash the first 32 bits of a byte sequence.

— Function **ctable.hashv_48** *ptr*

Hash the first 48 bits of a byte sequence.

— Function **ctable.hashv_64** *ptr*

Hash the first 64 bits of a byte sequence.
