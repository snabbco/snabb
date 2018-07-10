# LPM
`lib.lpm` provides a suite of Long Prefix Match algorithms for mapping IP
addresses to integer keys.
`lib.lpm.lpm4_trie` provides a basic patricia trie. It is relatively slow but
provides in place updates and is the basis for other faster lookup algorithms.
`lib.lpm.lpm4_248` provides DIR-24-8-BASIC
"Routing lookups in hardware at memory access speeds"
http://tiny-tera.stanford.edu/~nickm/papers/Infocom98_lookup.pdf
`lib.lpm.lpm4_dxr` provides a slightly modified DXR
"DXR: Towards a Billion Routing Lookups per Second in Software"
http://www.nxlab.fer.hr/dxr/
`lib.lpm.lpm4_poptrie` provides a work in progress implementation of poptrie.
"Poptrie: A Compressed Trie with Population Count for Fast and Scalable Software
IP Routing Table Lookup"
http://conferences.sigcomm.org/sigcomm/2015/pdf/papers/p57.pdf

3 fast algorithms are planned as benchmarking shows that performance of each
depends on the hardware platform chosen as well as the Prefix profile.
It is expected that a user would benchmark all 3 for their particular use case.

The interface below relies on string interaction as the internal representation
of ip addresses is still subject to change. Different representations have a
performance impact.

Method **lpm_imlementation:new** config
creates a new lpm object from the config table
`lpm4_trie` ignores config, defaults to
   `{ keybits = 15 }`
`lpm4_dxr` ignores config, defaults to
   `{ keybits = 15 }`
`lpm4_poptrie` ignores config, defaults to
   `{ keybits = 15 }`
`lpm4_248` supports keybits, the maximum size of a key in bits
   `{ keybits = 15 | 31 }`

Method **instance:add_string** cidr_string, key
key is any value > 0 and less than 2 ^ keybits - 1, if cidr_string already
exists key is updated

Method **instance:remove_string** cidr_string
Remove a prefix

Method **instance:search_string** ip_string
Returns key or undef if no prefix matches

Method **instance:search_bytes** ip_bytes_ptr
Returns key or undef if no prefix matches
ip_bytes_ptr points to an IP address as read off the wire, loosely speaking an
ip in network byte order

Method **instance:build**
Rebuild the lookup datastructure. Updates MAY not be reflected by search*
until build has been called.
