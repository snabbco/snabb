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

To create a ctable, first create a parameters table specifying the key
and value types, along with any other options.  Then call `ctable.new`
on those parameters.  For example:

```lua
local ctable = require('lib.ctable')
local ffi = require('ffi')
local params = {
   key_type = ffi.typeof('uint32_t'),
   value_type = ffi.typeof('int32_t[6]'),
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

Optional entries that may be present in the *parameters* table include:

 * `hash_seed`: A hash seed, as a 16-byte array.  The hash value of a
   key is a function of the key and also of the hash seed.  Using a
   hash function with a seed prevents some kinds of denial-of-service
   attacks against network functions that use ctables.  The seed
   defaults to a fresh random byte string.  The seed also changes
   whenever a table is resized.
 * `initial_size`: The initial size of the hash table, including free
   space.  Defaults to 8 slots.
 * `max_occupancy_rate`: The maximum ratio of `occupancy/size`, where
   `occupancy` denotes the number of entries in the table, and `size` is
   the total table size including free entries.  Trying to add an entry
   to a "full" table will cause the table to grow in size by a factor of
   2.  Defaults to 0.9, for a 90% maximum occupancy ratio.
 * `min_occupancy_rate`: Minimum ratio of `occupancy/size`.  Removing an
   entry from an "empty" table will shrink the table.
 * `resize_callback`: An optional function that is called after the
   table has been resized.  The function is called with two arguments:
   the ctable object and the old size. By default, no callback is used.
 * `max_displacement_limit`: An upper limit to extra slots allocated
   for displaced entries. By default we allocate `size*2` slots.
   If you carefully read *ctable.lua* you can set this to say 30 and
   thereby reduce memory usage to `size+2*30` slots.

— Function **ctable.load** *stream* *parameters*

Load a ctable that was previously saved out to a binary format.
*parameters* are as for `ctable.new`.  *stream* should be an object
that has a **:read_ptr**(*ctype*) method, which returns a pointer to
an embedded instances of *ctype* in the stream, advancing the stream
over the object; and **:read_array**(*ctype*, *count*) which is the
same but reading *count* instances of *ctype* instead of just one.

#### Methods

Users interact with a ctable through methods.  In these method
descriptions, the object on the left-hand-side of the method invocation
should be a ctable.

— Method **:resize** *size*

Resize the ctable to have *size* total entries, including empty space.

— Method **:add** *key*, *value*, *updates_allowed*

Add an entry to the ctable, returning the index of the added entry.
*key* and *value* are FFI values for the key and the value, of course.

*updates_allowed* is an optional parameter.  If not present or false,
then the `:insert` method will raise an error if the *key* is already
present in the table.  If *updates_allowed* is the string `"required"`,
then an error will be raised if *key* is *not* already in the table.
Any other true value allows updates but does not require them.  An
update will replace the existing entry in the table.

Returns a pointer to the inserted entry.  Any subsequent modification
to the table may invalidate this pointer.

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

— Method **:save** *stream*

Save a ctable to a byte sink.  *stream* should be an object that has a
**:write_ptr**(*ctype*) method, which writes an instance of a struct
type out to a stream, and **:write_array**(*ctype*, *count*) which is
the same but writing *count* instances of *ctype* instead of just one.

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

#### Streaming interface

As an implementation detail, the table is stored as an open-addressed
robin-hood hash table with linear probing.  Ctables use the
high-quality SipHash hash function to allow for good distribution of
hash values.  To find a value associated with a key, a ctable will
first hash the key, map that hash value to an index into the table by
scaling the hash to the table size, and then scan forward in the table
until we find an entry whose hash value is greater than or equal to
the hash in question.  Each entry stores its hash value, and empty
entries have a hash of `0xFFFFFFFF`.  If the entry's hash matches and
the entry's key is equal to the one we are looking for, then we have
our match.  If the entry's hash is greater than our hash, then we have
a failure.  Hash collisions are possible as well of course; in that
case we continue scanning forward.

The distance travelled while scanning for the matching hash is known as
the *displacement*.  The table measures its maximum displacement, for a
number of purposes, but you might be interested to know that a maximum
displacement for a table with 2 million entries and a 40% load factor is
around 8 or 9.  Smaller tables will have smaller maximum displacements.

The ctable has two lookup interfaces.  The first one is the `lookup`
methods described above.  The other interface will fetch all entries
within the maximum displacement into a buffer, then do a branchless
binary search over that buffer.  This second streaming lookup can also
fetch entries for multiple keys in one go.  This can amortize the cost
of a round-trip to RAM, in the case where you expect to miss cache for
every lookup.

To perform a streaming lookup, first prepare a `LookupStreamer` for
the batch size that you need.  You will have to experiment to find the
batch size that works best for your table's entry sizes; for
reference, for 32-byte entries a 32-wide lookup seems to be optimum.

```lua
-- Stream in 32 lookups at once.
local stride = 32
local streamer = ctab:make_lookup_streamer(stride)
```

Wiring up streaming lookup in a packet-processing network is a bit of
a chore currently, as you have to maintain separate queues of lookup
keys and packets, assuming that each lookup maps to a packet.  Let's
make a little helper:

```lua
local lookups = {
   queue = ffi.new("struct packet * [?]", stride),
   queue_len = 0,
   streamer = streamer
}

local function flush(lookups)
   if lookups.queue_len > 0 then
      -- Here is the magic!
      lookups.streamer:stream()
      for i = 0, lookups.queue_len - 1 do
         local pkt = lookups.queue[i]
         if lookups.streamer:is_found(i)
            local val = lookups.streamer.entries[i].value
            --- Do something cool here!
         end
      end
      lookups.queue_len = 0
   end
end

local function enqueue(lookups, pkt, key)
   local n = lookups.queue_len
   lookups.streamer.entries[n].key = key
   lookups.queue[n] = pkt
   n = n + 1
   if n == stride then
      flush(lookups)
   else
      lookups.queue_len = n
   end
end
```

Then as you see packets, you enqueue them via `enqueue`, extracting
out the key from the packet in some way and passing that value as the
argument.  When `enqueue` detects that the queue is full, it will
flush it, performing the lookups in parallel and processing the
results.
