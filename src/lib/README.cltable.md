### cltable (lib.cltable)

Ever been annoyed that you can't create a hash table where the keys are
FFI values, like raw IPv4 addresses, but the values are Lua objects?
Well of course you can key a normal Lua table by any Lua value, but the
key is looked up by identity and not by value, which is rarely what you
want.  `foo[lib.protocol.ipv4:pton('1.2.3.4')]` will not be the same as
`foo[lib.protocol.ipv4:pton('1.2.3.4')]`, as the `pton` call produces a
fresh value every time.  What you usually want with FFI-keyed tables is
to be able to look up the entry by value, not by identity.

Well never fear, *cltable* is here.  A cltable is a data type that
associates FFI keys with any old Lua value.  When you look up a key in a
cltable, the key is matched by-value.

Externally, a cltable provides the same interface as a Lua table, with
the exception that to iterate over the table's values, you need to use
`cltable.pairs` function instead of `pairs`.

Internally, cltable uses a [`ctable`](./README.ctable.md) to map the key
to an index, then if an entry is found, looks up that index in a side
table of Lua objects.  See the ctable documentation for more performance
characteristics.

To create a cltable, use pass an appropriate parameter table to
`cltable.new`, like this:

```lua
local cltable = require('lib.cltable')
local ffi = require('ffi')
local params = { key_type = ffi.typeof('uint8_t[4]') }
local cltab = cltable.new(params)
```

— Function **cltable.new** *parameters*

Create a new cltable.  *parameters* is a table of key/value pairs.  The
following key is required:

 * `key_type`: An FFI type (LuaJIT "ctype") for keys in this table.

Optional entries that may be present in the *parameters* table are
`hash_fn`, `initial_size`, `max_occupancy_rate`, and
`min_occupancy_rate`.  See the ctable documentation for their meanings.

— Function **cltable.build** *keys* *values*

Given the ctable *keys* that maps keys to indexes, and a corresponding
Lua table *values* containing the index->value associations, return a
cltable.

— Property **.keys**

A cltable's `keys` property holds the table's keys, as a ctable.  If you
modify it, you get to keep both pieces.

— Property **.values**

Likewise, a cltable's `values` property holds the table's values, as a
Lua array (table).  If you break it, you buy it!

— Function **cltable.pairs** *cltable*

Return an iterator over the keys and values in *cltable*.  Use this when
you would use `pairs` on a regular Lua table.
