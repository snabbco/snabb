### LISPER (program.lisper)

Snabb Switch program for overlaying Ethernet networks on the IPv6
Internet or a local IPv6 network. For transporting L2 networks over
the Internet, LISPER requires the use of external LISP (RFC 6830)
controllers.

#### Overview

LISPER transports L2 networks over an IPv6 network by connecting together
Ethernet networks and L2TPv3 point-to-point tunnels that are on different
locations on the transport network.

Each location runs an instance of LISPER and an instance of a LISP controller
to which multiple network interfaces can be connected.

Some of the interfaces can connect to physical Ethernet networks, others
can connect to IPv6 networks (routed or not). The IPv6 interfaces
carry packets to/from L2TPv3 tunnels and to/from remote LISPER instances.
The same IPv6 interface can connect to multiple tunnels and/or LISPER
instances so a single interface is sufficient to connect everything at one
location, unless there are direct Etherent networks which need connecting
too which require separate interfaces.

LISPER can work with to any Linux eth interface via raw sockets or it can
use its built-in Intel10G driver to work with Intel 82599 network cards
directly. The Intel10G driver also supports 802.1Q which allows multiple
virtual interfaces to be configured on a single network card.

#### Download

   https://github.com/capr/snabbswitch/archive/master.zip

#### Compile

```
make
```

#### Quick Demo

> Tested on Ubuntu 14.04 and NixOS 15.09.

```
cd src/program/lisper/dev-env

./net-bringup      # create a test network and start everything
./ping-all         # run ping tests
./net-bringdown    # kill everything and clean up
```

__NOTE:__ The test network creates network namespaces `r2` and `nodeN` where
`N=01..08` so make sure you don't use these namespaces already.

#### Run

```
src/snabb lisper -c <config.file>
```

#### Configure

The config file is a JSON file that looks like this:

```
{
   "control_sock" : "/var/tmp/lisp-ipc-map-cache04",
   "punt_sock"    : "/var/tmp/lispers.net-itr04",
   "arp_timeout"  : 60, // seconds

   "interfaces": [
      { "name": "e0",  "mac": "00:00:00:00:01:04",
                        "pci": "0000:05:00.0", "vlan_id": 2 },
      { "name": "e03", "mac": "00:00:00:00:01:03" },
      { "name": "e13", "mac": "00:00:00:00:01:13" }
   ],

   "exits": [
      { "name": "e0", "ip": "fd80:4::2", "interface": "e0",
         "next_hop": "fd80:4::1" }
   ],

   "lispers": [
      { "ip": "fd80:8::2", "exit": "e0" }
   ],

   "local_networks": [
      { "iid": 1, "type": "L2TPv3", "ip": "fd80:1::2", "exit": "e0",
         "session_id": 1, "cookie": "" },
      { "iid": 1, "type": "L2TPv3", "ip": "fd80:2::2", "exit": "e0",
         "session_id": 2, "cookie": "" },
      { "iid": 1, "interface": "e03" },
      { "iid": 1, "interface": "e13" }
   ]
}
```

Connectivity with the LISP controller requires `control_sock` and `punt_sock`,
two named sockets that must be the same sockets that the LISP controller
was configured with. These can be skipped if there's no LISP controller.

`interface` is an array defining the physical interfaces. `name` and `mac`
are required. If `pci` is given, the Intel10G driver is used.
If `vlan_id` is given, the interface is assumed to be a 802.1Q trunk.

`exits` is an array defining the IPv6 exit points (if any) which are used
for connecting to remote LISPER instances and to L2TPv3 tunnels. `name`,
`ip`, `interface`, `next_hop` are all required fields.

`lispers` is an array defining remote LISPER instances, if any.
`ip` and `exit` are required.

`local_networks` is an array defining the local L2 networks connected
to this LISPER instance. These can be either local networks (in which
case only `interface` is required) or L2TPv3 end-points (in which
case `type` must be "L2TPv3", and `ip`, `session_id`, `cookie` and `exit`
are required).

--

#### Demo/Test Suite

##### TL;DR

```
cd src/program/lisper/dev-env

./net-bringup             # create a test network and start everything
./net-bringup-intel10g    # create a test network using Intel10G cards
./ping-all                # run ping tests
./nsnode N                # get a shell in the network namespace of a node
./nsr2                    # get a shell in the network namespace of R2
./net-teardown            # kill everything and clean up
```

__NOTE:__ `net-bringup-intel10g` requires 4 network cards with loopback
cables between cards 1,2 and 3,4. Edit the script to set their names
and PCI addresses and also edit `lisperXX.conf.intel10g` config files
and change the `pci` and `vlan_id` fields as needed. You can find
the PCI addresses of the cards in your machine with `lspci | grep 82599`.

`./ping-all` sends 2000 IPv4 pings 1000-byte each between various nodes.
It's output should look like this:


```
l2tp-l2tp
2000 packets transmitted, 2000 received, 0% packet loss, time 443ms
2000 packets transmitted, 2000 received, 0% packet loss, time 603ms
l2tp-eth
2000 packets transmitted, 2000 received, 0% packet loss, time 358ms
2000 packets transmitted, 2000 received, 0% packet loss, time 502ms
eth-l2tp
2000 packets transmitted, 2000 received, 0% packet loss, time 354ms
2000 packets transmitted, 2000 received, 0% packet loss, time 507ms
l2tp-lisper-l2tp
2000 packets transmitted, 2000 received, 0% packet loss, time 1026ms
2000 packets transmitted, 2000 received, 0% packet loss, time 1037ms
eth-lisper-eth
2000 packets transmitted, 2000 received, 0% packet loss, time 926ms
2000 packets transmitted, 2000 received, 0% packet loss, time 876ms
```

##### What does it do

The test network is comprised of multiple network nodes that are all connected
to an R2 IPv6 router. The nodes are in different network namespaces and are
assigned IPs in different IPv6 subnets to simulate physical locations.

Node namespaces are named `nodeXX` where XX is 01, 02, 04, 05, 06 and 08.
The router lives in the `r2` namespace.

Nodes 01, 02, 05, 06 each contain both endpoints of an L2TPv3 tunnel.

Nodes 04, 08 each contain one LISPER instance and one local Ethernet network.

Each node has at least one interface in the L2 overlay network with
ip 10.0.0.N/24. You should be able to ping between any of them
(see `ping-all`).

Note the speed differences between nodes.
The worst case is if you go to node 01 (which contains 10.0.0.1
which is a L2TPv3 tunnel) and from there ping 10.0.0.5
(which is itself on a L2TPv3 tunnel on a remote LISPER).

#### Bugs and Limitations

- encryption between LISPER nodes is not implemented.
- L2 multicast is not implemented.
- `arp_timeout` config option is not followed.
- more testing with MAC addresses moving between locations is required.
- more performance testing and tuning is required.
- only one IPv6 exit-point per interface is supported.

