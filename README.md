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

## Documentation

None yet. The API follows that of the nDPI C library loosely, building on
metatypes to provide a more idiomatic feeling.

The following table summarizes the equivalence between C and Lua types:

| Lua Type | C Type |
|:--------:|:------:|
| `ndpi.detection_module` | `struct ndpi_detection_module_struct` |
| `ndpi.flow` | `struct ndpi_flow_struct` |
| `ndpi.id` | `struct ndpi_id_struct` |
| `ndpi.protocol_bitmask` | `NDPI_PROTOCOL_BITMASK` |


## Requirements

* [LuaJIT 2.0](http://www.luajit.org) or later.
* [nDPI 1.7][ndpi] or later.

## Installation

For the moment being, there is no automated installation: just place the
`ndpi` subdirectory and the `ndpi.lua` file in any location where LuaJIT
will be able to find them.

## License

All the `ljndpi` code is under the [MIT license](http://opensource.org/licenses/mit).


[ndpi]: http://www.ntop.org/products/deep-packet-inspection/ndpi/
