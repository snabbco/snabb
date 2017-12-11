### Ptree (program.ptree)

Example Snabb program for prototyping multi-process YANG-based network
functions.

#### Overview

The `lib.ptree` facility in Snabb allows network engineers to build a
network function out of a tree of processes described by a YANG schema.
The root process runs the management plane, and the leaf processes (the
"workers") run the data plane.  The apps and links in the workers are
declaratively created as a function of a YANG configuration.

This `snabb ptree` program is a tool to allow quick prototyping of
network functions using the ptree facilities.  The invocation syntax of
`snabb ptree` is as follows:

```
snabb ptree [OPTION...] SCHEMA.YANG SETUP.LUA CONF
```

The *schema.yang* file contains a YANG schema describing the network
function's configuration.  *setup.lua* defines a Lua function mapping a
configuration to apps and links for a set of worker processes.  *conf*
is the initial configuration of the network function.

#### Example: Simple packet filter

Let's say we're going to make a packet filter application.  We can use
Snabb's built-in support for filters expressed in pflang, the language
used by `tcpdump`, and just hook that filter up to a full-duplex NIC.

To begin with, we have to think about how to represent the configuration
of the network function.  If we simply want to be able to specify the
PCI device of a NIC, an RSS queue, and a filter string, we could
describe it with a YANG schema like this:

```yang
module snabb-pf-v1 {
  namespace snabb:pf-v1;
  prefix pf-v1;

  leaf device { type string; mandatory true; }
  leaf rss-queue { type uint8; default 0; }
  leaf filter { type string; default ""; }
}
```

We throw this into a file `pf-v1.yang`.  In YANG, a `module`'s
body contains configuration declarations, most importantly `leaf`,
`container`, and `list`.  In our `snabb-pf-v1` schema, there is a
`module` containing three `leaf`s: `device`, `rss-queue`, and `filter`.
Snabb effectively generates a validating parser for configurations
following this YANG schema; a configuration file must contain exactly
one `device FOO;` declaration and may contain one `rss-queue` statement
and one `filter` statement.  Thus a concrete configuration following
this YANG schema might look like this:

```
device 83:00.0;
rss-queue 0;
filter "tcp port 80";
```

So let's just drop that into a file `pf-v1.cfg` and use that as our
initial configuration.

Now we just need to map from this configuration to app graphs in some
set of workers.  The *setup.lua* file should define this function.

```
-- Function taking a snabb-pf-v1 configuration and
-- returning a table mapping worker ID to app graph.
return function (conf)
   -- Write me :)
end
```

The `conf` parameter to the setup function is a Lua representation of
config data for this network function.  In our case it will be a table
containing the keys `device`, `rss_queue`, and `filter`.  (Note that
Snabb's YANG support maps dashes to underscores for the Lua data, so it
really is `rss_queue` and not `rss-queue`.)

The return value of the setup function is a table whose keys are "worker
IDs", and whose values are the corresponding app graphs.  A worker ID
can be any Lua value, for example a number or a string or whatever.  If
the user later reconfigures the network function (perhaps setting a
different filter string), the manager will re-run the setup function to
produce a new set of worker IDs and app graphs.  The manager will then
stop workers whose ID is no longer present, start new workers, and
reconfigure workers whose ID is still present.

In our case we're just going to have one worker, so we can use any
worker ID.  If the user reconfigures the filter but keeps the same
device and RSS queue, we don't want to interrupt packet flow, so we want
to use a worker ID that won't change.  But if the user changes the
device, probably we do want to restart the worker, so maybe we make the
worker ID a function of the device name.

With all of these considerations, we are ready to actually write the
setup function.

```lua
local app_graph = require('core.config')
local pci = require('lib.hardware.pci')
local pcap_filter = require('apps.packet_filter.pcap_filter')

-- Function taking a snabb-pf-v1 configuration and
-- returning a table mapping worker ID to app graph.
return function (conf)
   -- Load NIC driver for PCI address.
   local device_info = pci.device_info(conf.device)
   local driver = require(device_info.driver).driver

   -- Make a new app graph for this configuration.
   local graph = app_graph.new()
   app_graph.app(graph, "nic", driver,
                 {pciaddr=conf.device, rxq=conf.rss_queue,
                  txq=conf.rss_queue})
   app_graph.app(graph, "filter", pcap_filter.PcapFilter,
                 {filter=conf.filter})
   app_graph.link(graph, "nic."..device.tx.." -> filter.input")
   app_graph.link(graph, "filter.output -> nic."..device.rx)

   -- Use DEVICE/QUEUE as the worker ID.
   local id = conf.device..'/'..conf.rss_queue

   -- One worker with the given ID and the given app graph.
   return {[id]=graph}
end
```

Put this in, say, `pf-v1.lua`, and we're good to go.  The network
function can be run like this:

```
snabb ptree --name my-filter pf-v1.yang pf-v1.lua pf-v1.cfg
```

See [`snabb ptree --help`](./README) for full details on arguments like
`--name`.

#### Tuning

(Document scheduling parameters here.)

#### Reconfiguration

(Document "snabb config" and NCS integration here.)

#### Multi-process

(Make a multi-process yang model here.)
