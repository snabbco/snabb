# Configuration

The lwAFTR's configuration is modelled by a
[YANG](https://tools.ietf.org/html/rfc6020) schema,
[snabb-softwire-v3](../../../lib/yang/snabb-softwire-v3.yang).

The lwAFTR takes its configuration from the user in the form of a text
file.  That file's grammar is derived from the YANG schema; see the
[Snabb YANG README](../../../lib/yang/README.md) for full details.
Here's an example:

```
softwire-config {
  instance {
    device "00:05.0"
    queue {
      id 0;
      external-interface {
        ip 10.10.10.10;
        mac 12:12:12:12:12:12;
        // vlan-tag 42;
        next-hop {
          mac 68:68:68:68:68:68;
          ip 1.2.3.4;
        }
      }
      internal-interface {
        ip 8:9:a:b:c:d:e:f;
        mac 22:22:22:22:22:22;
        // vlan-tag 64;
        next-hop {
          mac 44:44:44:44:44:44;
          // NDP instead of ARP of course.
          ip 7:8:9:a:b:c:d:e;
        }
      }
    }
  }

  // IPv4 interface.
  external-interface {
    allow-incoming-icmp true;
    // Limit ICMP error transmit rate to PACKETS/PERIOD.
    error-rate-limiting {
      packets 600000;
      period 2;
    }
    // Generate ICMP errors at all?
    generate-icmp-errors true;
    // Basic parameters.
    mtu 1460;
    // Where to go next.  Either one will suffice; if you specify the IP,
    // the next-hop MAC will be determined by ARP.
    // Control the size of the fragment reassembly buffer.
    reassembly {
      max-fragments-per-packet 40;
      max-packets 20000;
    }
  }
  // The same thing as for the external interface, but on the IPv6 side
  // and with IPv6 addresses.
  internal-interface {
    allow-incoming-icmp true;
    error-rate-limiting {
      packets 600000;
      period 2;
    }
    generate-icmp-errors true;
    // One more interesting thing -- here we control whether to support
    // routing traffic between two B4s.
    hairpinning true;
    mtu 1500;
    reassembly {
      max-fragments-per-packet 40;
      max-packets 20000;
    }
  }
  // Now the binding table!
  binding-table {
    softwire {
      ipv4 178.79.150.233;
      psid 22788;
      b4-ipv6 127:11:12:13:14:15:16:128;
      br-address 8:9:a:b:c:d:e:f;
      psid-map {
        psid-length 16;
      }
    }
    softwire {
      ipv4 178.79.150.233;
      psid 2700;
      b4-ipv6 127:11:12:13:14:15:16:128;
      br-address 8:9:a:b:c:d:e:f;
      psid-map {
        psid-length 16;
      }
    }
    softwire {
      ipv4 178.79.150.15;
      psid 1;
      b4-ipv6 127:22:33:44:55:66:77:128;
      br-address 8:9:a:b:c:d:e:f;
      psid-map {
        psid-length 4;
      }
    }
    softwire {
      ipv4 178.79.150.2;
      psid 7850;
      b4-ipv6 127:24:35:46:57:68:79:128;
      br-address 1e:1:1:1:1:1:1:af;
      psid-map {
        psid-length 16;
      }
    }
  }
}
```

The lwaftr will spawn a number of worker processes that perform packet
forwarding.  Each `queue` statement in the configuration corresponds to
one process servicing one RSS queue on one or two network devices.  For
on-a-stick operation, only the `device` leaf will be specified.
For bump-in-the-wire operation, `device` will handle IPv6 traffic, and
IPv4 traffic will be handled on the device specified in the
`external-device` leaf.

The `external-interface` define parameters around the IPv4 interface
that communicates with the internet and the `internal-interface` section
does the same but for the IPv6 side that communicates with the
B4s. Anything that is in the `external-interface` or
`internal-interface` blocks outside of the `instance` list are shared
amongst all instances. The binding table then declares the set of
softwires and the whole thing is surrounded in the `softwire-config {
... }` block.

## Compiling configurations

When a lwAFTR is started, it will automatically compile its
configuration if it does not find a compiled configuration that's fresh.
However for large configurations with millions of binding table entries,
this can take a second or two, so it can still be useful to compile the
configuration ahead of time.

Use the `snabb lwaftr compile-configuration` command to compile a
configuration ahead of time.  If you do this, you can use the `snabb
config load PID /path/to/file` command to tell the Snabb process with
the given *PID* to reload its configuration from the given file.

## In-depth configuration explanation

See the embedded descriptions in the
[snabb-softwire-v3](../../../lib/yang/snabb-softwire-v3.yang) schema
file.

## Binding tables

A binding table is a collection of softwires (tunnels).  One endpoint
of the softwire is in the AFTR and the other is in the B4.  A
softwire provisions an IPv4 address (or a part of an IPv4 address) to
a customer behind a B4.  The B4 arranges for all IPv4 traffic to be
encapsulated in IPv6 and sent to the AFTR; the AFTR does the reverse.
The binding table is how the AFTR knows which B4 is associated with
an incoming packet.

In the Snabb lwAFTR there is a single softwire container in binding
table.

### Softwires

The `softwire` clauses define the set of softwires to provision.  Each
softwire associates an IPv4 address, a PSID, and a B4 address. It also
contains a `port-set` container which defines the IPv4 address that has
been provisioned by an lwAFTR. See RFC 7597 for more details on the PSID
scheme for how to share IPv4 addresses.

For example:

```
  softwire {
    ipv4 178.79.150.233;
    psid 80;
    b4-ipv6 127:2:3:4:5:6:7:128;
    br-address 8:9:a:b:c:d:e:f
    port-set {
      psid-length 6;
      reserved-ports-bit-count 0;
    }
  }
```

`reserved-ports-bit-count` in the `port-set` container is optional.

An entry's `psid-length` and `reserved-ports-bit-count` must not exceed
16 when summed. The shift parameter is calculated from the two parameters
in this equation:

   shift = 16 - `psid-length` + `reserved-ports-bit-count`

## Ingress and egress filters

Both the `internal-interface` and `external-interface` configuration
blocks support `ingress-filter` and `egress-filter` options.
```
...
ingress-filter "ip";
egress-filter "ip";
```

If given these filters should be a
[pflang](https://github.com/Igalia/pflua/blob/master/doc/pflang.md)
filter.  Pflang is the language of `tcpdump`, `libpcap`, and other
tools.

If an ingress or egress filter is specified in the configuration file,
then only packets which match that filter will be allowed in or out of
the lwAFTR.  It might help to think of the filter as being "whitelists"
-- they pass only what matches and reject other things.  To make a
"blacklist" filter, use the `not` pflang operator:

```
// Reject IPv6.
ingress-filter "not ip6";
```

You might need to use parentheses so that you are applying the `not` to
the right subexpression.  Note also that if you have 802.1Q vlan tagging
enabled, the ingress and egress filters run after the tags have been
stripped.

Here is a more complicated example:

```
egress-filter "
  ip6 and not (
    (icmp6 and
     src net 3ffe:501:0:1001::2/128 and
     dst net 3ffe:507:0:1:200:86ff:fe05:8000/116)
    or
    (ip6 and udp and
     src net 3ffe:500::/28 and
     dst net 3ffe:0501:4819::/64 and
     src portrange 2397-2399 and
     dst port 53)
  )
";
```

Enabling ingress and egress filters currently has a performance cost.
See [performance.md](performance.md).

## Multiple devices

One lwAFTR can run multiple worker processes.  For example, here is a
configuration snippet that specifies two on-a-stick processes that
service traffic on PCI addresses `83:00.0` and `83:00.1`:

```
  instance {
    device 83:00.0;
    queue {
      id 0;
      external-interface {
        ip 10.10.10.10;
        mac 02:12:12:12:12:12;
        next-hop { mac 02:44:44:44:44:44; }
      }
      internal-interface {
        ip 8:9:a:b:c:d:e:f;
        mac 02:12:12:12:12:12;
        next-hop { mac 02:44:44:44:44:44; }
      }
    }
  }

  instance {
    device 83:00.1;
    queue {
      id 0;
      external-interface {
        ip 10.10.10.10;
        mac 56:56:56:56:56:56;
        next-hop { mac 02:68:68:68:68:68; }
      }
      internal-interface {
        ip 8:9:a:b:c:d:e:f;
        mac 56:56:56:56:56:56;
        next-hop { mac 02:68:68:68:68:68; }
      }
    }
  }
```

Here you see that the two blocks are the same, except that the `device`
in the second `instance` is `83:00.1` instead of `83:00.0`.  The layer-2
`mac` addresses for the two interfaces within each instance are the same
because this is an on-a-stick configuration, and likewise for the
next-hops.  Although instance `83:00.0` has different `mac` addresses
from instance `83:00.1`, the two instances have the same `ip` addresses.
Usually the idea is that the whole bank of lwAFTRs are reachable at the
layer-3 address, and it's up to some other router to shard traffic
between the interfaces.

The `id` leaf that's part of the `queue` container specifies the
Receive-Side Scaling (RSS) queue ID that a worker should service.  For
example, here's a bump-in-the-wire configuration with two RSS workers:

```
  instance {
    device 83:00.0;
    external-device 83:00.1;
    queue {
      id 0;
      external-interface {
        ip 10.10.10.10;
        mac 56:56:56:56:56:56;
        next-hop { mac 02:68:68:68:68:68; }
      }
      internal-interface {
        ip 8:9:a:b:c:d:e:f;
        mac 56:56:56:56:56:56;
        next-hop { mac 02:68:68:68:68:68; }
      }
    }
    queue {
      id 1;
      external-interface {
        ip 10.10.10.10;
        mac 56:56:56:56:56:56;
        next-hop { mac 02:68:68:68:68:68; }
      }
      internal-interface {
        ip 8:9:a:b:c:d:e:f;
        mac 56:56:56:56:56:56;
        next-hop { mac 02:68:68:68:68:68; }
      }
    }
  }
```

These queues are configured on the `83:00.0` instance, and because the
instance specifies an `external-device` this is a bump-in-the-wire
configuration.  The two queues are identical with the exception of their
`id` fields.  Incoming IPv6 traffic on `83:00.0` and IPv4 traffic on
`83:00.1` will be evenly split between these two worker processes using
RSS hashing.

For reasons specific to the 82599 NIC, the RSS `id` can currently be
only `0` or `1`.  Expanding the range will be possible in the future.
The actual value of the ID doesn't matter; you can have a lwAFTR running
with only RSS queue 0 or only RSS queue 1, and in both cases that worker
process will get all the traffic.  Traffic is split only when multiple
queues are configured.

Which queue is chosen for any given packet is determined by the RSS hash
function.  The RSS hash function will take the source and destination IP
addresses (version 4 or 6 as appropriate) together with the source and
destination ports (for TCP or UDP packets) and use them to compute a
hash value.  The NIC then computes the remainder when that hash value is
divided by the number of queues, and then uses that remainder as an
index to select a queue from among the available queues.

In the encapsulation direction (IPv4 to IPv6), all inputs to the RSS
hash function will be available, except for the case of incoming ICMP
packets and for incoming fragmented traffic.  This should yield good
distribution of the traffic among available queues.  However in the
decapsulation direction (IPv6 to IPv4), the destination IPv6 address is
a constant (it's the address of the lwAFTR) and there are no ports as
the upper-layer protocol is IPv4 instead of TCP or UDP.  The only
contributor for entropy in the decapsulation direction is the source
IPv6 address.  All decapsulation traffic from a given softwire will thus
be handled by the same lwAFTR instance, provided the router's ECMP
function also performs a similarly deterministic function to choose the
device to which to send the packets.

## Run-time reconfiguration

See [`snabb config`](../../config/README.md) for a general overview of
run-time configuration query and update in Snabb.  By default, the
lwAFTR is addressable using the
[`ietf-softwire-br`](../../../lib/yang/ietf-softwire-br.yang) YANG
schema.  The lwAFTR also has a "native" schema that exposes more
configuration information,
[`snabb-softwire-v3`](../../../lib/yang/snabb-softwire-v3.yang).  Pass
the `-s` argument to the `snabb config` tools to specify a non-default
YANG schema.

As an example of `snabb config` usage, here is how to change the
next-hop address of the external interface on lwaftr instance `lwaftr`'s
queue `0` on device `83:00.0`:

```
$ snabb config set -s snabb-softwire-v3 lwaftr \
    /softwire-config/instance[device=83:00.0]/queue[id=0]/external-interface/next-hop/mac \
    02:02:02:02:02:02
```

`snabb config` can also be used to add and remove instances at run-time.

Firstly, we suggest getting a lwAFTR configuration working that runs on
only one interface and one queue.  Once you have that working, do a
`snabb config get -s snabb-softwire-v3 lwaftr /softwire-config/instance`
to get the `instance` configuration for the `lwaftr` instance.  You'll
get something like this:

```
{
  device 83:00.0;
  queue {
    id 0;
    external-interface { ... };
    internal-interface { ... };
  }
}
```

So to add another device, you can just paste that into a file, change the
devices, and then do:

```
$ snabb config add -s snabb-softwire-v3 lwaftr \
    /softwire-config/instance < my-instance.file.conf
```

If all goes well, you should be able to get `/softwire-config/instance`
again and that should show you two instances running.

Likewise to add an RSS worker, it's the same except you work on
`/softwire-config/instance[device=XX:XX.X]/queue`.

Getting the MAC addresses right is tricky of course; the NIC filters
incoming traffic by MAC, and if you've configured a queue or device with
the wrong MAC, you might wonder why none of your packets are getting
through!  Unfortunately these counters are not exposed by the lwaftr, at
least not currently, but you can detect this situation if the
`in-ipv6-packets` or `in-ipv4-packets` counters are not incrementing
like you think they should be.

To remove a queue, use `snabb config remove`:

```
$ snabb config remove -s snabb-softwire-v3 lwaftr \
    /softwire-config/instance[device=XX:XX.X]/queue[id=ID]
```

Likewise you can remove instances this way:

```
$ snabb config remove -s snabb-softwire-v3 lwaftr \
    /softwire-config/instance[device=XX:XX.X]
```

Of course all of this also works via `snabb config listen`, for nice
integration with NETCONF agents.
