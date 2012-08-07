# The Snabb Switch Project

The Snabb Switch is a virtualized Ethernet switch for cloud computing.
The switch connects all physical and virtual Ethernet ports in the
server farm and enforces all the policies peculiar to your own network.

The project is very young. Congratulations, you've found us early!

## Why the Snabb Switch Project?

The Snabb Switch Project is motivated by the sense that there is a
better way to do high-speed networking in the 21st-century. The
project is a vehicle for discovering this way.

The first steps in the implementation are to pay the price of entry to
be a practical Ethernet switch. The moment this is done we will seek
out niches where the Snabb Switch can solve important problems for
people who're operating big networks.

## Design

The Snabb Switch design is inspired by Emacs. There is a top layer of
software written in a high-level language,
[LuaJIT](http://luajit.org/), and a bottom layer of software written
in a low-level language, C. Initially most of the software is written
in LuaJIT, and over time more functionality will migrate down to C,
and a neat and stable interface will emerge.

LuaJIT and C were chosen because they're technically suitable and
they're readily accessible to a lot of people.

The switch is purely user-space and it doesn't depend on networking
functionality of the operating system. This buys us a lot of
flexibility that we need to put to good use. We'll also use nifty
tricks to have performance that's at least as good as kernel-based
switches.

There will be a lot of churn of code and ideas in the early days of
the project. Over time we will find the simplest and best ways to do
everything. On the way we'll surely try things that don't turn out as
clever as we'd hoped. Such is the joy of software development!

## Current status

Just getting started. We have the beginnings of a switch, and the
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
kvm ... -net nic,vlan=1 -net snabb_shm,vlan=1,file=/tmp/a ...
```

There's much potential for enhancement.

This software exists in the [`shm` branch of Snabb fork of QEMU](https://github.com/SnabbCo/QEMU/tree/shm). Check out the [diff](https://github.com/SnabbCo/QEMU/compare/master...shm) compared to QEMU.

### `bin/snabb switch, src/lua/switch.lua`

Ethernet switch written mostly in LuaJIT. It uses snabb_shm shared
memory ethernet interfaces (above) for packet I/O. Currently it's
really low on functionality, mostly untested, and lacking interfaces
towards the host OS or physical NICs.

There is support for dumping all switch traffic to a PCAP/tcpdump file
for analysis and verification. The switch sneakily appends metadata to
each packet in the trace declaring ingress vs. egress and switch port
ID.

### `bin/snabb checktrace, src/lua/checktrace.lua`

Switch functionality testing. Take a PCAP/tcpdump file for input and
check it for correctness. That is: make sure packet's don't loop back
to the port they come from, that multicasts flood out every port, and
so on. This is the basis for the software testing strategy:
post-processing to make sure the switch behaved well when bombarded
with arbitrary workloads.

### `bin/snabb tracemaker, src/lua/tracemaker.lua`

Create PCAP files exhibiting invalid switch behavior, e.g. dropped or
looped packets. These files are used for testing the tester i.e.
making sure it detects the errors. They are essentially unit tests.

### `bin/snabb test, test/checker.tush, tools/tush`

Top-level entry point to test the Snabb Switch. Uses Darius Bacon's
'tush' program to execute the tracemaker and tester.

## Roadmap

The first major milestone will be stable and fast basic switching
between hosts and hypervisors with a small and tight code base. The
next features will be driven by the needs of the initial users, the
people whose needs aren't met by the currently available switches.

Here's a dreamed up list of potential features, just to give an idea:

- New platform support e.g. VirtualBox on Windows.
- Integrated device driver for 10G networking e.g. Intel 82599 chip.
- Switch-on-a-card deployment on Intel Cave Creek network processor PCIe cards.
- Distributed operation with native L2-in-L3 tunneling.
- OpenFlow support.

We'll see what people really need. Should be wild fun :-).

## Get involved

The Snabb Switch Project is very transparent and open to the public.
You're more than welcome to join in the fun.

### Github

Snabb's development is hosted on Github:

- https://github.com/SnabbCo/snabbswitch is the main software repository.
- https://github.com/SnabbCo/QEMU is the fork of QEMU with user-space ethernet I/O support.

To contribute to the Snabb Switch, simply fork these repositories,
make some improvements, and send in a pull request on Github. Let's
start simple and tune the process over time.

Ideally developers will collaborate mostly through the medium of code
on Github. Maybe we won't even need a mailing list in the beginning.
We shall see!

### Reddit

The Snabb Switch Project community reddit is at
[snabb.reddit.com](http://snabb.reddit.com/). This is the place to
post and discuss links to anything that's relevant to the
project.

### Twitter

Twitter is a handy way to become part of the Snabb universe.

- `#snabb` hashtag: you can use this freely to say things about the project.
- Links to [Gists](http://opensource.org/licenses/gpl-2.0.php) can be used for email-length comments.

### Mailing list

Today there's no mailing list in active use. There may be one in the future if Github + Twitter aren't sufficient.

## Who

The Snabb Switch project is founded by [Luke
Gorrie](http://lukego.com/). Luke's company [Snabb
GmbH](http://www.snabb.co/) has the mission to steward the Snabb
software development, to provide both free and commercial services to
the software's users, and to create opportunities for other people and
companies to offer services too. Luke's goal is to create a happy
ecosystem of mutually beneficial parties. You are welcome to join in.

## License

The Snabb Switch is dual-licensed free software. Everybody is able to
use the software under the terms of the [GNU General Public License
v2](http://opensource.org/licenses/gpl-2.0.php). Snabb GmbH also
offers commercial licenses to companies who want to integrate Snabb
technology into their products, or people who want to create startup
companies based on Snabb technology.

Contributions to the Snabb Switch use either joint copyright between
Snabb GmbH and the author or are simply BSD licensed. This follows the
example of projects such as OpenNMS, QT, MySQL, BerkeleyDB,
VirtualBox, and so on.

