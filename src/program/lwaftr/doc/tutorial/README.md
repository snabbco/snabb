# Getting Started with Snabb lwAFTR

## Installation

Clone the Snabb repository to get the latest [release](https://github.com/snabbco/snabb/releases/):

```
$ git clone https://github.com/snabbco/snabb.git
```

If you don’t have `git` you can also download a Zip archive or Tarball of the latest release and unpack that.

Next compile Snabb by running

```
$ cd snabb # where you cloned or unpacked Snabb
$ git checkout lwaftr-tutorial # XXX: bug fixes applying to this guide
$ make
... # a bunch of output that you should be able to safely ignore
BINARY    5.4M snabb # this should be the second-last line of output and indicates success
```

The result should be a Snabb executable located at `src/snabb`.
You can copy this binary to any location of your choosing, or execute from there as it is.

## Configuring lwAFTR

To run Snabb lwAFTR you need an initial configuration file.
You can find a minimal, commented example configuration to adapt to your needs here:
[src/program/lwaftr/doc/tutorial/lwaftr-start.conf.yang](lwaftr-start.conf.yang)

For a complete documentation of Snabb lwAFTR configuration refer to its [YANG schema](https://github.com/snabbco/snabb/blob/master/src/lib/yang/snabb-softwire-v3.yang).

## Running Snabb lwAFTR

You can test the Snabb executable you compiled by running
```
$ sudo src/snabb lwaftr run --help
```
which should print a listing of available command line options for Snabb lwAFTR.

> Note that Snabb always needs to be run with superuser privileges, hence we use "sudo".
> This is because Snabb directly accesses network hardware, bypassing the Linux OS.

To run Snabb lwAFTR for real, download the example configuration and save it as `lwaftr-start.conf.yang`.
You probably need to edit at least the `device` and `external-device` statements for the configuration to apply
to your system.

You can then run Snabb lwAFTR like so:

```
$ sudo src/snabb lwaftr run --name "my-lwaftr" --cpu 12-23 --conf lwaftr-start.conf.yang
```

The command line options mean:

 - `--name`: a name for this lwAFTR process used to refer to it in supporting programs: `snabb config get/set/get-state`
 - `--cpu`: a CPU core range used by lwAFTR
 - `--conf`: file from which to read the initial configuration

## Supporting programs: snabb config get/set/get-state

> XXX: TODO

## Example: testing Snabb lwAFTR within a virtual Linux network namespace

You can try out Snabb lwAFTR on virtual Linux interfaces.
There is an example setup described in [src/program/lwaftr/doc/tutorial/lwaftr-veth-env.sh](lwaftr-veth-env.sh)

```
$ sudo src/snabb lwaftr run --name testaftr --v6 aftrv6 --v4 aftrv4 --conf lwaftr-start.conf.yang &
lwaftr-start.conf.yang: loading source configuration
lwaftr-start.conf.yang: wrote compiled configuration lwaftr-start.conf.yang.o
Migrating instance '0000:85:00.0' to 'aftrv6'
No CPUs available; not binding to any NUMA node.
Warning: No assignable CPUs declared; leaving data-plane PID 1581617 without assigned CPU.
NDP: Resolving 'fd10::10'
ARP: Resolving '10.77.0.10'
NDP: 'fd10::10' resolved (76:6c:8a:be:20:27)
ARP: '10.77.0.10' resolved (42:06:59:b2:3c:6d)
```

```
$ sudo ip netns exec aftrint ping -c 1 fd10::1
PING fd10::1(fd10::1) 56 data bytes
64 bytes from fd10::1: icmp_seq=1 ttl=64 time=0.164 ms

--- fd10::1 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 0.164/0.164/0.164/0.000 ms
```

```
$ sudo ip netns exec aftrext ping -c 1 10.77.0.1
PING 10.77.0.1 (10.77.0.1) 56(84) bytes of data.
64 bytes from 10.77.0.1: icmp_seq=1 ttl=64 time=0.207 ms

--- 10.77.0.1 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 0.207/0.207/0.207/0.000 ms
```

```
 $ sudo ip netns exec aftrint tcpdump -nn -i internal -l --immediate-mode &
[2] 1797194
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on internal, link-type EN10MB (Ethernet), capture size 262144 bytes

$ sudo ip netns exec aftrext ping -c 1 -W 1 198.18.0.1
PING 198.18.0.1 (198.18.0.1) 56(84) bytes of data.
15:53:05.495202 IP6 2003:1b0b:fff9:ffff::4001 > 2003:1c09:ffe0:100::1: IP 10.77.0.10 > 198.18.0.1: ICMP echo request, id 29506, seq 1, length 64


--- 198.18.0.1 ping statistics ---
1 packets transmitted, 0 received, 100% packet loss, time 0ms
```

```
$ sudo src/snabb config get-state -s snabb-softwire-v3 testaftr /softwire-state | grep -v ' 0;'
discontinuity-time 2022-07-28T14:37:04Z;
drop-all-ipv6-iface-bytes 3648;
drop-all-ipv6-iface-packets 24;
drop-unknown-protocol-ipv6-bytes 3648;
drop-unknown-protocol-ipv6-packets 24;
in-arp-reply-bytes 42;
in-arp-reply-packets 1;
in-arp-request-bytes 210;
in-arp-request-packets 5;
in-icmpv4-echo-bytes 588;
in-icmpv4-echo-packets 6;
in-icmpv6-echo-bytes 472;
in-icmpv6-echo-packets 4;
in-ipv4-bytes 2646;
in-ipv4-frag-reassembly-unneeded 39;
in-ipv4-packets 27;
in-ipv6-bytes 4050;
in-ipv6-frag-reassembly-unneeded 49;
in-ipv6-packets 27;
in-ndp-na-bytes 554;
in-ndp-na-packets 7;
in-ndp-ns-bytes 774;
in-ndp-ns-packets 9;
memuse-ipv4-frag-reassembly-buffer 728203264;
memuse-ipv6-frag-reassembly-buffer 11378176;
out-arp-reply-bytes 210;
out-arp-reply-packets 5;
out-arp-request-bytes 42;
out-arp-request-packets 1;
out-icmpv4-echo-bytes 588;
out-icmpv4-echo-packets 6;
out-icmpv4-error-bytes 222;
out-icmpv4-error-packets 3;
out-icmpv6-echo-bytes 472;
out-icmpv6-echo-packets 4;
out-ipv4-bytes 222;
out-ipv4-frag-not 15;
out-ipv4-packets 3;
out-ipv6-bytes 3726;
out-ipv6-frag-not 35;
out-ipv6-packets 27;
out-ndp-na-bytes 258;
out-ndp-na-packets 3;
out-ndp-ns-bytes 86;
out-ndp-ns-packets 1;
```
