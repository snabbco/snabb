# nDPI FFI binding for LuaJIT

`ljndpi` is a Lua [FFI](http://luajit.org/ext_ffi.html) binding for the
[nDPI][ndpi] deep packet inspection library.

## Usage

The following program skeleton outlines the usage of the module:

```lua
local ndpi = require "ndpi"
local TICK_RESOLUTION = 1000  -- Samples per second
local detector = ndpi.detection_module(TICK_RESOLUTION)
detector:set_protocol_bitmask(ndpi.protocol_bitmask():set_all())

local flows = {}
for packet in iterate_packets() do
  -- Obtain a unique identifier for a flow, most likely using
  -- the source/destination IP addresses, ports, and VLAN tag.
  local flow_id = get_flow_id(packet)
  local flow = flows[flow_id]
  if not flow then
    -- Add any other flow-specific information needed by your application.
    flow = {
      ndpi_flow = ndpi.flow(),
      ndpi_src_id = ndpi.id(),
      ndpi_dst_id = ndpi.id(),
      protocol = ndpi.protocol.PROTOCOL_UNKNOWN,
    }
    flows[flow_id] = flow
  end

  if flow.protocol ~= ndpi.protocol.PROTOCOL_UNKNOWN then
    print("Identified protocol: " .. ndpi.protocol[flow.protocol])
  else
    flow.protocol = detector:process_packet(flow.ndpi_flow,
                                            get_ip_data_pointer(packet),
                                            get_ip_data_length(packet),
                                            os.time(),
                                            flow.ndpi_src_id,
                                            flow.ndpi_dst_id)
  end
end
```

## Requirements

* [LuaJIT 2.0](http://www.luajit.org) or later.
* [nDPI 1.7][ndpi] or later.

## Installation

Using [LuaRocks](https://luarocks.org) is recommended. The latest stable
release can be installed with:

```sh
luarocks install ljndpi
```

The current development version can be installed with:

```sh
luarocks install --server=https://luarocks.org/dev ljndpi
```

Alternatively, you can just place the `ndpi` subdirectory and the `ndpi.lua`
file in any location where LuaJIT will be able to find them.


## Documentation

None yet. The API follows that of the nDPI C library loosely, building on
metatypes to provide a more idiomatic feeling. For the moment the best option
is to check the [example
program](https://github.com/aperezdc/ljndpi/blob/master/examples/readpcap).

The following table summarizes the equivalence between C and Lua types:

| Lua Type | C Type |
|:---------|:-------|
| `ndpi.detection_module` | `struct ndpi_detection_module_struct` |
| `ndpi.flow` | `struct ndpi_flow_struct` |
| `ndpi.id` | `struct ndpi_id_struct` |
| `ndpi.protocol_bitmask` | `NDPI_PROTOCOL_BITMASK` |

As for the functions, they can be accessed Lua's method invocation syntax
(`foo:bar()`), for example the following C code:

```c
#define TICKS 1000
NDPI_PROTOCOL_BITMASK all_bits;
NDPI_BITMASK_SET_ALL(all_bits);
struct ndpi_detection_module_struct *dm =
        ndpi_init_detection_module(TICKS, malloc, free, NULL);
ndpi_set_protocol_detection_bitmask2(dm, &all_bits);
```

becomes:

```lua
local TICKS = 1000
local all_bits = ndpi.protocol_bitmask()
all_bits:set_all()
local dm = ndpi.detection_module(TICKS)
dm:set_protocol_bitmask(all_bits)
```

Note that many methods return the objects themselves, allowing for chained
method calls, which allows the above snippet to be simplified into:

```lua
local TICKS = 1000
local dm = ndpi.detection_module(TICKS):set_protocol_bitmask(ndpi.protocol_bitmask():set_all())
```

The “nDPI QuickStart Guide” from the
[ntop documentation downloads
section](http://www.ntop.org/support/documentation/documentation/) is helpful
to get overview of how to use nDPI, which also applies to using `ljndpi`.


## Bugs

Check the [issue tracker](https://github.com/aperezdc/ljndpi/issues) for known
bugs, and please file a bug if you find one.


## License

All the `ljndpi` code is under the [Apache
License 2.0](http://www.apache.org/licenses/). A copy of the license is
included in the [COPYING](COPYING) file in the source distribution.

### Historical Note

Versions prior to `0.1.0` are under the terms of the [MIT/X11
license](https://opensource.org/licenses/mit). Versions `0.1.0` and `0.0.3`
only differ in their license.


## Authors

`ljndpi` was written by Adrián Pérez at [Igalia S.L.](http://www.igalia.com),
initially as part of [SnabbWall](http://snabbwall.org). Development was
sponsored by the [NLnet Foundation](https://nlnet.nl/).

![](http://snabbwall.org/images/igalia-logo.png) &nbsp;&nbsp;
![](http://snabbwall.org/images/nlnet-logo.gif)

Feedback is very welcome! If you are interested in `ljndpi` in a Snabb
context, probably the best thing is to post a message to the
[snabb-devel](https://groups.google.com/forum/#!forum/snabb-devel) group. Or,
if you like, you can contact Adrián directly at `aperez@igalia.com`. If you
have a problem that `ljndpi` can help solve, let us know!

[ndpi]: http://www.ntop.org/products/deep-packet-inspection/ndpi/
