![Snabb](snabb.png)

# Snabb

Snabb (formerly "Snabb Switch") is a simple and fast packet networking toolkit.

We are also a grassroots community of programmers and network
engineers who help each other to build and deploy new network
elements. We care about practical applications and finding simpler
ways to do things.

The Snabb community are active in
[applying modern programming techniques](http://blog.ipspace.net/2014/09/snabb-switch-deep-dive-on-software-gone.html),
[do-it-yourself operator networking](http://blog.ipspace.net/2014/12/l2vpn-over-ipv6-with-snabb-switch-on.html),
[high-level device drivers](https://github.com/snabbco/snabb/blob/master/src/apps/intel/intel10g.lua),
[fast userspace virtio networking](http://www.virtualopensystems.com/en/solutions/guides/snabbswitch-qemu/),
[universal SIMD protocol offloads](https://groups.google.com/d/msg/snabb-devel/aez4pEnd4ow/WrXi5N7nxfkJ), and
[applying compiler technology to networking](https://archive.fosdem.org/2015/schedule/event/packet_filtering_pflua/).

You are welcome to join our community! Scroll down to the bottom for
tips on how you can get involved.

## Documentation

- [API Reference](http://snabbco.github.io/)
- [Contributor Hints](https://github.com/snabbco/snabb/blob/master/CONTRIBUTING.md#hints-for-contributors)

## How does it work?

Snabb is written using these main techniques:

- Lua, a high-level programming language that is easy to learn.
- LuaJIT, a just-in-time compiler that is competitive with C.
- Ethernet I/O with no kernel overhead ("kernel bypass" mode).

Snabb compiles into a stand-alone executable called
`snabb`. This single binary includes multiple applications and runs on
any modern [Linux/x86-64](src/doc/porting.md) distribution. (You could
think of it as a
[busybox](https://en.wikipedia.org/wiki/BusyBox#Single_binary) for
networking.)

## How is it being used?

The first generation of Snabb applications include:

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

### lwAFTR

[Snabb lwAFTR](src/program/lwaftr/) is the internet-facing component of
"lightweight 4-over-6" (lw4o6), an IPv6 transition technology.  An ISP
can use lwAFTR functions to provide its users with access to the IPv4
internet while maintaining a simple IPv6-only internal network.  An ISP
deploying Snabb lwAFTR can also configure lw4o6 to share IPv4 addresses
between multiple different customers, ameliorating the IPv4 address
space exhaustion problem and lowering costs.  See the [lwAFTR
documentation](src/program/lwaftr/doc/) for more details.

### VPWS

VPWS (Virtual Private Wire Service) is a Layer-2 VPN application being
developed by Alexander Gall at [SWITCH](http://www.switch.ch/). His Github
[`vpn` branch](https://github.com/alexandergall/snabbswitch/tree/vpn)
is the master line of development.

### packetblaster

[packetblaster](src/program/packetblaster/) generates load by
replaying a [pcap format](https://en.wikipedia.org/wiki/Pcap) trace
file or synthesizing customizable packets onto any number of Intel 82599 10-Gigabit network
interfaces. This is very efficient: only a small % of one core per CPU
is required even for hundreds of Gbps of traffic. Because so little
CPU resources are required you can run packetblaster on a small server
or even directly on a Device Under Test.

### snsh

[snsh](src/program/snsh/) (Snabb Shell) is a tool for interactively
experimenting with Snabb. It provides direct access to all APIs
using a Lua shell. You can operate snsh either from script files or
from an interactive shell.

## How do I get started?

Setting up a Snabb development environment takes around one
minute:

```
$ git clone https://github.com/SnabbCo/snabb
$ cd snabb
$ make -j
$ sudo src/snabb --help
```

The `snabb` binary is stand-alone, includes all of the applications,
and can be copied between machines.

For example, to install on the local machine and use as a load generator:

```
$ cp src/snabb /usr/local/bin/
$ sudo snabb packetblaster replay capture.pcap 01:00.0
```

### snabb container

Basic support for building and running snabb in a Docker container is available via

```
$ make docker
```

This will build a tiny snabb container (8MB), ready to be used:

```
$ docker run -ti --rm snabb --help
```

Or simply run snabb, as you would under linux. This is made possible by using a wrapper shell script that
gets linked to as part of 'make docker':

```
$ src/snabb --help
```

## How do I get involved?

Here are the ways you can get involved:

- Use the Snabb applications in your network.
- Create your very own application: [Getting Started](src/doc/getting-started.md).
- Create Github Issues with your ideas and questions and problems.
- [Join](https://join.slack.com/t/snabb/shared_invite/enQtMzIyOTIwMTg5ODYyLWUwYzg2MTIwMjAxZTM1N2RlNGFjMWY1YzRkZGZiN2U5ZGU1NTYwNWJiMmQ3MWQ1MDFjYTg0MjNjNTZjMTFlZGQ) the [Snabb Slack chat](https://snabb.slack.com/) to hang out and shoot the breeze.

