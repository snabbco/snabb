
# The Snabb Switch Project

<a href="http://www.snabb.co"><img align="right"
src="http://www.snabb.co/snabb-tiger-medium.png"/></a> The Snabb
Switch project is developing a virtualized hypervisor Ethernet switch
for cloud computing. The switch will connect all the physical and
virtual Ethernet ports in the data center and enforce all the policies
peculiar to your the network.

The project is very young. Congratulations, you've found us early!

## Why the Snabb Switch Project?

The Snabb Switch project is motivated by the sense that there is a
better way to do high-speed networking in the 21st-century. The
project is a vehicle for discovering the way.

The first steps in the implementation are the absolute basics needed
to be a practical Ethernet switch. The moment this is done we will
seek out niches where the Snabb Switch can solve important problems
for people who are operating big networks.

## Design

The Snabb Switch design is inspired by Emacs. There is a top layer of
software written in a high-level language,
[LuaJIT](http://luajit.org/), and a bottom layer of software written
in a low-level language, C. Initially most of the software is written
in LuaJIT, and over time more functionality will migrate down to C,
and a neat and stable interface will emerge.

LuaJIT and C were chosen because they're technically suitable and
they're readily accessible to a lot of people.

The switch is purely user-space and it does not depend on networking
functionality from the operating system. This buys us a lot of
flexibility that we need to put to good use. We will also use nifty
tricks to have performance that is at least as good as kernel-based
switches.

There will be a lot of churn of code and ideas in the early days of
the project. Over time we will find the simplest and best ways to do
everything. On the way we will surely try things that don't turn out
as clever as we had hoped. Such is the joy of software development!

## Current status

Just getting started. We have the beginnings of a switch and the
beginnings of KVM/QEMU hypervisor integration.

## Software overview

Here's a quick overview of the main pieces of software. Except where
otherwise stated, these are all a part of the
[`snabbswitch`](https://github.com/SnabbCo/snabbswitch) repository on
github.

### KVM/QEMU snabb_shm support

Backend for KVM/QEMU network devices to read/write ethernet frames to
files. If those files are created in /dev/shm/ on Linux then this
functions as an efficient user-space shared-memory virtual ethernet.

The support works. Here's an example of how to use it:

```
kvm ... -net nic,vlan=1 -net snabb_shm,vlan=1,file=/tmp/shmeth0 ...
```

There's much potential for enhancement.

This software exists in the [`shm` branch of Snabb fork of QEMU](https://github.com/SnabbCo/QEMU/tree/shm). Check out the [diff](https://github.com/SnabbCo/QEMU/compare/master...shm) compared to QEMU.

### `bin/snabb switch` [`src/lua/switch.lua`](https://github.com/SnabbCo/snabbswitch/blob/master/src/lua/switch.lua)

Ethernet switch logic in LuaJIT. Written as a library. Currently low
on functionality, mostly untested, and lacking interfaces towards the
host OS or physical NICs.

There is support for dumping all switch traffic to a PCAP/tcpdump file
for analysis and verification. The switch sneakily appends metadata to
each packet in the trace declaring ingress vs. egress and switch port
ID.

### `bin/snabb checktrace` [`src/lua/checktrace.lua`](https://github.com/SnabbCo/snabbswitch/blob/master/src/lua/checktrace.lua)

Switch functionality testing. Take a PCAP/tcpdump file for input and
check it for correctness. That is: make sure packet's don't loop back
to the port they come from, that multicasts flood out every port, and
so on. This is the basis for the software testing strategy:
post-processing to make sure the switch behaved well when bombarded
with arbitrary workloads.

### `bin/snabb replay <input> <output>` [`src/lua/checktrace.lua`](https://github.com/SnabbCo/snabbswitch/blob/master/src/lua/replay.lua)

Test switch functionality by replaying packets from a recorded trace
and recording the switch's behavior to an output trace. The output
trace can later be checked with `checktrace`.

### `bin/snabb maketraces` [`src/lua/tracemaker.lua`](https://github.com/SnabbCo/snabbswitch/blob/master/src/lua/tracemaker.lua)

Create PCAP files exhibiting invalid switch behavior, e.g. dropped or
looped packets. These files are used for testing the tester i.e.
making sure it detects the errors. They are essentially unit tests.

### `bin/snabb test, test/checker.tush, tools/tush`

Top-level entry point to test the Snabb Switch. Uses Darius Bacon's
'tush' program to execute the tracemaker and tester. Verify that a
correct trace passes all tests, and that an incorrect trace for each
error class fails.

## Roadmap

The rough roadmap for Snabb Switch now is:

- Basic switching functionality.
- Powerful testing framework.
- Switch-to-Host integration.
- Switch-to-NIC integration.
- Optimized performance.
- Distributed operation.

This will be heavily influenced by the early users and the reasons why
they have found existing solutions such as Open vSwitch unsuitable.

## Get involved

The Snabb Switch Project is very transparent and open to the public.
You're more than welcome to join in the fun.

### Github

Snabb's development is hosted on Github:

- https://github.com/SnabbCo/snabbswitch is the main software repository.
- https://github.com/SnabbCo/QEMU is the fork of QEMU with user-space ethernet I/O support.

To contribute to the Snabb Switch, simply fork these repositories,
make some improvements, and send in a pull request on Github. Let's
start simple and tune the process over time. It will be interesting to
get some experience with how versatile Github's tools are.

### Reddit

The Snabb Switch Project community reddit is at
[snabb.reddit.com](http://snabb.reddit.com/). This is the place to
post and discuss links to anything that's relevant to the
project.

### Mailing list

Today there's no mailing list. Let's first see how much of what we need can be provided by Github.

## Who

The Snabb Switch project is founded by [Luke
Gorrie](http://lukego.com/) and his company
[Snabb](http://www.snabb.co/). You are welcome to participate in the
community.

## License

The Snabb Switch is dual-licensed free software. You can use it as
free and open source software under the terms of the [Snabb
License](http://www.snabb.co/SnabbLicense.html) or you can buy a
license for proprietary use from [Snabb](http://www.snabb.co/).

Snabb has to be able to legally distribute contributions to both open
source and proprietary users of Snabb Switch. This means that in order
to accept your contribution we must ask you to do either one of two
things:

1. License your contribution under the liberal MIT License.
2. Fill out the [Snabb Contributor Agreement](http://www.snabb.co/SCA.pdf). This can be done quickly online without paper. Contact luke@snabb.co.

