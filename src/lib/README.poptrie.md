### Poptrie (lib.poptrie)

An implementation of
[Poptrie](http://conferences.sigcomm.org/sigcomm/2015/pdf/papers/p57.pdf).
Includes high-level functions for building the Poptrie data structure, as well
as a hand-written, optimized assembler lookup routine.

#### Example usage

```lua
local pt = poptrie.new{}
-- Associate prefixes of length to values (uint16_t)
pt:add(0x00FF, 8, 1)
pt:add(0x000F, 4, 2)
pt:build()
pt:lookup64(0x001F) ⇒ 2
pt:lookup64(0x10FF) ⇒ 1
-- The value zero denotes "no match"
pt:lookup64(0x0000) ⇒ 0
-- You can create a pre-built poptrie from nodes and leaves arrays.
local pt2 = poptrie.new{nodes=pt.nodes, leaves=pt.leaves}
```

#### Known bugs and limitations

 - Only supports keys up to 64 bits wide
 - *Direct pointing* is not yet implemented

#### Performance

```
PMU analysis (numentries=10000, keysize=64)
lookup: 30001.41 cycles/lookup 59357.23 instructions/lookup
lookup64: 179.39 cycles/lookup 205.72 instructions/lookup
```

#### Interface

— Function **new** *init*

Creates and returns a new `Poptrie` object.

*Init* is a table with the following keys:

* `leaves` - *Optional*. An array of leaves. When *leaves* is supplied *nodes*
   must be supplied as well.
* `nodes` - *Optional*. An array of nodes. When *nodes* is supplied *leaves*
   must be supplied as well.

— Method **Poptrie:add** *prefix* *length* *value*

Associates *value* to *prefix* of *length*. *Prefix* must be an unsigned
integer (little-endian) of up to 64 bits. *Length* must be an an unsigned
integer between 1 and 64. *Value* must be a 16‑bit unsigned integer, and should
be greater than zero (see `lookup64` as to why.)

— Method **Poptrie:build**

Compiles the optimized poptrie data structure used by `lookup64`. After calling
this method, the *leaves* and *nodes* fields of the `Poptrie` object will
contain the leaves and nodes arrays respectively. These arrays can be used to
construct a `Poptrie` object.

— Method **Poptrie:lookup64** *key*

Looks up *key* in the `Poptrie` object and returns the associated value or
zero. *Key* must be an unsigned, little-endian integer of up to 64 bits.

Unless the `Poptrie` object was initialized with leaves and nodes arrays, the
user must call `Poptrie:build` before calling `Poptrie:lookup64`.
