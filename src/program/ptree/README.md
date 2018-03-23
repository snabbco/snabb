### Ptree (program.ptree)

Example Snabb program for prototyping multi-process YANG-based network
functions.

#### Overview

The [`lib.ptree`](../../lib/ptree/README.md) facility in Snabb allows
network engineers to build a network function out of a tree of processes
described by a [YANG schema](../../lib/yang/README.md).  The root
process runs the management plane, and the leaf processes (the
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
   app_graph.link(graph, "nic."..device_info.tx.." -> filter.input")
   app_graph.link(graph, "filter.output -> nic."..device_info.rx)

   -- Use DEVICE/QUEUE as the worker ID.
   local id = conf.device..'/'..conf.rss_queue

   -- One worker with the given ID and the given app graph.
   return {[id]=graph}
end
```

Put this in, say, `pf-v1.lua`, and we're good to go.  The network
function can be run like this:

```
$ snabb ptree --name my-filter pf-v1.yang pf-v1.lua pf-v1.cfg
```

See [`snabb ptree --help`](./README) for full details on arguments like
`--name`.

#### Tuning

The `snabb ptree` program also takes a number of options that apply to
the data-plane processes.

— **--cpu** *cpus*

Allocate *cpus* to the data-plane processes.  The manager of the process
tree will allocate CPUs from this set to data-plane workers.  For
example, For example, `--cpu 3-5,7-9` assigns CPUs 3, 4, 5, 7, 8, and 9
to the network function.  The manager will try to allocate a CPU for a
worker that is NUMA-local to the PCI devices used by the worker.

— **--real-time**

Use the `SCHED_FIFO` real-time scheduler for the data-plane processes.

— **--on-ingress-drop** *action*

If a data-plane process detects too many dropped packets (by default,
100K packets over 30 seconds), perform *action*.  Available *action*s
are `flush`, which tells Snabb to re-optimize the code; `warn`, which
simply prints a warning and raises an alarm; and `off`, which does
nothing.

#### Reconfiguration

The manager of a ptree-based Snabb network function also listens to
configuration queries and updates on a local socket.  The user-facing
side of this interface is [`snabb config`](../config/README.md).  A
`snabb config` user can address a local ptree network function by PID,
but it's easier to do so by name, so the above example passed `--name
my-filter` to the `snabb ptree` invocation.

For example, we can get the configuration of a running network function
with `snabb config get`: 

```
$ snabb config get my-filter /
device 83:00.0;
rss-queue 0;
filter "tcp port 80";
```

You can also update the configuration.  For example, to move this
network function over to device `82:00.0`, do:

```
$ snabb config set my-filter /device 82:00.0
$ snabb config get my-filter /
device 82:00.0;
rss-queue 0;
filter "tcp port 80";
```

The ptree manager takes the necessary actions to update the dataplane to
match the specified configuration.

#### Multi-process

Let's say your clients are really loving this network function, so much
so that they are running an instance on each network card on your
server.  Whenever the filter string updates though they are getting
tired of having to `snabb config set` all of the different processes.
Well you can make them even happier by refactoring the network function
to be multi-process.

```yang
module snabb-pf-v2 {
  namespace snabb:pf-v2;
  prefix pf-v2;

  /* Default filter string.  */
  leaf filter { type string; default ""; }

  list worker {
    key "device rss-queue";
    leaf device { type string; }
    leaf rss-queue { type uint8; }
    /* Optional worker-specific filter string.  */
    leaf filter { type string; }
  }
}
```

Here we declare a new YANG model that instead of having one device and
RSS queue, it has a whole list of them.  The `key "device rss-queue"`
declaration says that the combination of device and RSS queue should be
unique -- you can't have two different workers on the same device+queue
pair, logically.  We declare a default `filter` at the top level, and
also allow each worker to override with their own filter declaration.

A configuration might look like this:

```
filter "tcp port 80";
worker {
  device 83:00.0;
  rss-queue 0;
}
worker {
  device 83:00.0;
  rss-queue 1;
}
worker {
  device 83:00.1;
  rss-queue 0;
  filter "tcp port 443";
}
worker {
  device 83:00.1;
  rss-queue 1;
  filter "tcp port 443";
}
```

Finally, we need a new setup function as well:

```lua
local app_graph = require('core.config')
local pci = require('lib.hardware.pci')
local pcap_filter = require('apps.packet_filter.pcap_filter')

-- Function taking a snabb-pf-v2 configuration and
-- returning a table mapping worker ID to app graph.
return function (conf)
   local workers = {}
   for k, v in pairs(conf.worker) do
      -- Load NIC driver for PCI address.
      local device_info = pci.device_info(k.device)
      local driver = require(device_info.driver).driver

      -- Make a new app graph for this worker.
      local graph = app_graph.new()
      app_graph.app(graph, "nic", driver,
                    {pciaddr=k.device, rxq=k.rss_queue,
                     txq=k.rss_queue})
      app_graph.app(graph, "filter", pcap_filter.PcapFilter,
                    {filter=v.filter or conf.filter})
      app_graph.link(graph, "nic."..device_info.tx.." -> filter.input")
      app_graph.link(graph, "filter.output -> nic."..device_info.rx)

      -- Use DEVICE/QUEUE as the worker ID.
      local id = k.device..'/'..k.rss_queue

      -- Add worker with the given ID and the given app graph.
      workers[id] = graph
   end
   return workers
end
```

If we place these into analogously named files, we have a multiprocess
network function:

```
$ snabb ptree --name my-filter pf-v2.yang pf-v2.lua pf-v2.cfg
```

If you change the root filter string via `snabb config`, it propagates
to all workers, except those that have their own overrides of course:

```
$ snabb config set my-filter /filter "'tcp port 666'"
$ snabb config get my-filter /filter
"tcp port 666"
```

The syntax to get at a particular worker is a little gnarly; it's based
on XPath, for compatibility with existing NETCONF NCS systems.  See [the
`snabb config` documentation](../config/README.md) for full details.

```
$ snabb config get my-filter '/worker[device=83:00.1][rss-queue=1]'
filter "tcp port 443";
```

You can stop a worker with `snabb config remove`:

```
$ snabb config remove my-filter '/worker[device=83:00.1][rss-queue=1]'
$ snabb config get my-filter /
filter "tcp port 666";
worker {
  device 83:00.0;
  rss-queue 0;
}
worker {
  device 83:00.0;
  rss-queue 1;
}
worker {
  device 83:00.1;
  rss-queue 0;
  filter "tcp port 443";
}
```

Start up a new one with `snabb config add`:

```
$ snabb config add my-filter /worker <<EOF
{
  device 83:00.1;
  rss-queue 1;
  filter "tcp port 8000";
}
EOF
```

Voilà!  Now your clients will think you are a wizard!
