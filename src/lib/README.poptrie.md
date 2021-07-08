### Poptrie (lib.poptrie)

An implementation of
[Poptrie](http://conferences.sigcomm.org/sigcomm/2015/pdf/papers/p57.pdf).
Includes high-level functions for building the Poptrie data structure, as well
as a hand-written, optimized assembler lookup routine.

#### Example usage

```lua
local pt = poptrie.new{direct_pointing=true}
-- Associate prefixes of length to values (uint16_t)
pt:add(ipv4:pton("192.168.0.0"), 16, 1)
pt:add(ipv4:pton("192.0.0.0"), 8, 2)
pt:build()
pt:lookup32(ipv4:pton("192.1.2.3")) ⇒ 2
pt:lookup32(ipv4:pton("192.168.2.3")) ⇒ 1
-- The value zero denotes "no match"
pt:lookup32(ipv4:pton("193.1.2.3")) ⇒ 0
-- You can create a pre-built poptrie from its backing memory.
local pt2 = poptrie.new{
   nodes = pt.nodes,
   leaves = pt.leaves,
   directmap = pt.directmap
}
```

#### Performance

Note that performance tends to be memory-bound. The results below reflect ideal
conditions with hot caches. See [Benchmarking Poptrie](https://mr.gy/blog/poptrie-dynasm.html#section-5).

- Intel(R) Xeon(R) CPU E3-1246 v3 @ 3.50GHz (Haswell, Turbo off)

```
PMU analysis (numentries=10000, numhit=100, keysize=32)
build: 0.1857 seconds
lookup: 8460.17 cycles/lookup 18089.70 instructions/lookup
lookup32: 62.71 cycles/lookup 99.99 instructions/lookup
lookup64: 64.11 cycles/lookup 100.00 instructions/lookup
lookup128: 74.44 cycles/lookup 118.66 instructions/lookup
build(direct_pointing): 0.1676 seconds
lookup(direct_pointing): 1306.68 cycles/lookup 3146.96 instructions/lookup
lookup32(direct_pointing): 35.49 cycles/lookup 62.61 instructions/lookup
lookup64(direct_pointing): 35.95 cycles/lookup 62.61 instructions/lookup
lookup128(direct_pointing): 37.75 cycles/lookup 66.81 instructions/lookup
```

#### Interface

— Function **new** *init*

Creates and returns a new `Poptrie` object.

*Init* is a table with the following keys:

* `direct_pointing` - *Optional*. Boolean that governs whether to use the
  *direct pointing* optimization. Default is `false`.
* `s` - *Optional*. Bits to use for the *direct pointing* optimization.
  Default is 18. Note that the direct map array will be 2×2ˢ bytes in size.
* `leaves` - *Optional*. An array of leaves. When *leaves* is supplied *nodes*
   must be supplied as well.
* `nodes` - *Optional*. An array of nodes. When *nodes* is supplied *leaves*
   must be supplied as well.
* `directmap` - *Optional*. A direct map array. When *directmap* is supplied,
   *nodes* and *leaves* must be supplied as well and *direct_pointing* is
   implicit.

— Method **Poptrie:add** *prefix* *length* *value*

Associates *value* to *prefix* of *length*. *Prefix* must be a `uint8_t *`
pointing to at least `math.ceil(length/8)` bytes. *Length* must be an integer
equal to or greater than 1. *Value* must be a 16‑bit unsigned integer, and
should be greater than zero (see `lookup*` as to why.)

— Method **Poptrie:build**

Compiles the optimized poptrie data structure used by `lookup64`. After calling
this method, the *leaves* and *nodes* fields of the `Poptrie` object will
contain the leaves and nodes arrays respectively. These arrays can be used to
construct a `Poptrie` object.


— Method **Poptrie:lookup32** *key*

— Method **Poptrie:lookup64** *key*

— Method **Poptrie:lookup128** *key*

Looks up *key* in the `Poptrie` object and returns the associated value or
zero. *Key* must be a `uint8_t *` pointing to at least 4/8/16 bytes
respectively.

Unless the `Poptrie` object was initialized with leaves and nodes arrays, the
user must call `Poptrie:build` before calling `Poptrie:lookup64`.

It is an error to call these lookup routines on poptries that contain prefixes
longer than supported by the individual lookup routine. I.e., you can only call
`lookup64` on poptries with prefixes of less than or equal to 64 bits.
