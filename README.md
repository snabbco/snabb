# Snabb Switch

Snabb Switch is a simple and fast packet networking toolkit.

We are also a grassroots community of programmers and network
engineers who help each other to build and deploy new network
elements. We care about practical applications and finding simpler
ways to do things.

The Snabb Switch community are active in
[applying modern programming techniques](http://blog.ipspace.net/2014/09/snabb-switch-deep-dive-on-software-gone.html),
[do-it-yourself operator networking](http://blog.ipspace.net/2014/12/l2vpn-over-ipv6-with-snabb-switch-on.html),
[high-level device drivers](https://github.com/SnabbCo/snabbswitch/blob/master/src/apps/intel/intel10g.lua),
[fast userspace virtio networking](http://www.virtualopensystems.com/en/solutions/guides/snabbswitch-qemu/),
[universal SIMD protocol offloads](https://groups.google.com/d/msg/snabb-devel/aez4pEnd4ow/WrXi5N7nxfkJ), and
[applying compiler technology to networking](https://fosdem.org/2015/schedule/event/packet_filtering_pflua/).

You are welcome to join our community. If you have an application that
you want to build, or you want to use one that we are already
developing, or you want to contribute in some other way, then please
join the [snabb-devel mailing
list](https://groups.google.com/forum/#!forum/snabb-devel) and read
on.

## How does it work?

Snabb Switch is written using these main techniques:

- Lua, a high-level programming langauge that is easy to learn.
- LuaJIT, a just-in-time compiler that is competitive with C.
- Ethernet I/O with no kernel overhead ("kernel bypass" mode).

Snabb Switch compiles into a stand-alone executable called
`snabb`. This single binary includes many applications ([like
busybox](http://en.wikipedia.org/wiki/BusyBox#Single_binary)) and runs
on any modern Linux distribution.

## How is it being used?

The first generation of Snabb Switch applications include:

### snabbnfv

[Snabb NFV](src/program/snabbnfv/) makes QEMU/KVM networking
performance practical for applications that require high packet rates,
such as ISP core routers. This is intended for people who want to
process up to 100 Gbps or 50 Mpps of Virtio-net network traffic per
server. We originally developed Snabb NFV to support Deutsche
Telekom's [TeraStream](https://ripe67.ripe.net/archives/video/3/)
network.

You can deploy Snabb NFV stand-alone with QEMU or you can integrate it
with a cloud computing platform such as OpenStack.

### VPWS

VPWS (Virtual Private Wire Service) is a Layer-2 VPN application being
developed by Alexander Gall at [SWITCH](http://switch.ch). His Github
[`vpn` branch](https://github.com/alexandergall/snabbswitch/tree/vpn)
is the master line of development.

### packetblaster

[packetblaster](src/program/packetblaster/) generates load by
replaying a [pcap format](http://en.wikipedia.org/wiki/Pcap) trace
file onto any number of Intel 82599 10-Gigabit network
interfaces. This is very efficient: only a small % of one core per CPU
is required even for hundreds of Gbps of traffic. Because so little
CPU resources are required you can run packetblaster on a small server
or even directly on a Device Under Test.

### snsh

[snsh](src/program/snsh/) (Snabb Shell) is a tool for interactively
experimenting with Snabb Switch. It provides direct access to all APIs
using a Lua shell. You can operate snsh either from script files or
from an interactive shell.

## How do I get started?

Setting up a Snabb Switch development environment takes around one
minute:

```
$ git clone https://github.com/SnabbCo/snabbswitch
$ cd snabbswitch
$ make -j
$ src/snabb --help
```

The `snabb` binary is stand-alone, includes all of the applications,
and can be copied between machines.

For example, to install on the local machine and use as a load generator:

```
$ cp src/snabb /usr/local/bin/
$ sudo snabb packetblaster capture.pcap 0000:01:00.0
```

## How do I get involved?

*To be written*
