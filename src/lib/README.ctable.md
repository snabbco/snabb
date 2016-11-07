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

Hash values are unsigned 32-bit integers in the range `[0,
0xFFFFFFFF)`.  That is to say, `0xFFFFFFFF` is the only unsigned 32-bit
integer that is not a valid hash value.  The `hash_fn` must return a
hash value in the correct range.

Optional entries that may be present in the *parameters* table include:

 * `hash_fn`: A function that takes a key and returns a hash value.
   If not given, defaults to the result of calling `compute_hash_fn`
   on the key type.
 * `initial_size`: The initial size of the hash table, including free
   space.  Defaults to 8 slots.
 * `max_occupancy_rate`: The maximum ratio of `occupancy/size`, where
   `occupancy` denotes the number of entries in the table, and `size` is
   the total table size including free entries.  Trying to add an entry
   to a "full" table will cause the table to grow in size by a factor of
   2.  Defaults to 0.9, for a 90% maximum occupancy ratio.
 * `min_occupancy_rate`: Minimum ratio of `occupancy/size`.  Removing an
   entry from an "empty" table will shrink the table.

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

— Function **ctable.compute_hash_fn** *ctype*

Return a `hashv_`-like hash function over the bytes in instances of
*ctype*.  Note that the same reservations apply as for `hash_32`
above.
