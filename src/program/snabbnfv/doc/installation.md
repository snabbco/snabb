# Installation

Here are some tips for how to relate the software
[Architecture](architecture.md) to nuts and bolts like files to install
and init scripts to write.

## Software installation

There is only one file to install: the `snabb` executable.

To create this file you can checkout the
[snabbswitch](https://github.com/SnabbCo/snabbswitch/) repository and run
`make` at the top level to produce `src/snabb`. You can install this in a
standard location such as `/usr/bin/snabb`.

`snabb` is a stand-alone executable that contains all of the required
functions as sub-commands (in the style of busybox).

The relevant usages are:

* [`snabb snabbnfv traffic ...`](https://github.com/SnabbCo/snabbswitch/tree/master/src/program/snabbnfv/traffic)
  on the compute node does the traffic processing.

* [`snabb snabbnfv neutron-sync-master ...`](https://github.com/SnabbCo/snabbswitch/tree/master/src/program/snabbnfv/neutron_sync_master)
  on the database node(s) makes the Neutron configuration available to
  compute nodes. 

* [`snabb snabbnfv neutron-sync-agent ...`](https://github.com/SnabbCo/snabbswitch/tree/master/src/program/snabbnfv/neutron_sync_agent)
  on the compute nodes to poll the master for configuration updates.

* [`snabb snabbnfv neutron2snabb ...`](https://github.com/SnabbCo/snabbswitch/tree/master/src/program/snabbnfv/neutron2snabb)
  to translate the Neutron database into configuration files for the local traffic processes. This command is called automatically from `neutron-sync-agent`.

The `traffic` command has no external software dependencies. Other
commands expect certain programs to be in the `PATH` to call: `snabb`,
`git`, `mysqldump`, `diff`, and standard shellutils.

## What to run

These are the services that should run in addition to OpenStack itself:

* `neutron-sync-master`: One instance per database server.
* `neutron-sync-agent`: One instance per compute node.
* `traffic`: One instance per 10G traffic port on each compute node.

The command line arguments for each process can be determined by reading
the usage and considering whether the default is suitable.

The processes print log messages to stdout and these should be redirected
to a suitable location such as syslog.

## Traffic process

### Configuration

You do not have to write configuration files for the traffic
application. These are generated automatically by `neutron_sync_agent`
based on the Neutron database configuration.

### CPU affinity

The traffic process should run on a reserved CPU core (see [[Compute node
requirements]]). The core can be assigned with `taskset -c <core> snabb
snabbnfv traffic ...`.

Note: The command `numactl` seems to be incompatible with the Linux
`isolcpus` feature and for this reason it is not recommended.

The designated core should be selected from a NUMA node that corresponds
to the PCI device the traffic process is attaching to. Checking the NUMA
node assignment for device 0000:00:03. can be done like this:

```
cat /sys/bus/pci/devices/0000:00:03.0/numa_node
```

### `traffic` restarts

The traffic process is designed to be safe to restart. If it detects an
error it will terminate with a message and expect to be restarted. Once
restarted it will continue serving traffic for the virtual
machines. (Stateful packet filtering connection tables are reset during
restarts, however.)

We recommend that the traffic process is always restarted automatically
when it terminates, after some reasonable delay (e.g. between one and ten
seconds).
