# Configuration

## SnabbVMX's configuration file

SnabbVMX has its own configuration file (example: **snabbvmx-lwaftr-xe0.cfg**).
The configuration file is actually a Lua file, that is processed by the
`snabbvmx lwaftr` command.

It contains a reference to a Snabb's **lwAFTR** configuration file (which
contains a reference to a binding table).

**snabbvmx-lwaftr-xe0.cfg**

```lua
return {
   lwaftr = "snabbvmx-lwaftr-xe0.conf",
   ipv6_interface = {
      cache_refresh_interval = 1,
      mtu = 9500,
   },
   ipv4_interface = {
      ipv4_address = "10.0.1.1",
      cache_refresh_interval = 1,
      mtu = 1460,
   },
   settings = {
      vlan = 421,
   }
}
```

SnabbVMX defines extra configuration parameters for `ipv4_interface`/`ipv6_interface`
(deactivate/activate fragmentation, dynamic/static next-hop resolution, MTU).
In addition, it also allows a `settings` option for extra configuration.

## Snabb's lwAFTR configuration files

SnabbVMX's configuration file `lwaftr` attribute points to a Snabb's lwAFTR
configuration file.  This configuration file keeps a reference to a
binding table, among other information, which is an important piece of a
lwAFTR deployment.

Here is how a lwAFTR configuration file looks like:

```
binding_table = binding_table.txt,
vlan_tagging = false,
aftr_ipv6_ip = fc00::100,
aftr_mac_inet_side = 02:AA:AA:AA:AA:AA,
inet_mac = 02:99:99:99:99:99,
ipv6_mtu = 9500,
policy_icmpv6_incoming = DROP,
policy_icmpv6_outgoing = DROP,
icmpv6_rate_limiter_n_packets = 6e5,
icmpv6_rate_limiter_n_seconds = 2,
aftr_ipv4_ip = 10.0.1.1,
aftr_mac_b4_side = 02:AA:AA:AA:AA:AA,
next_hop6_mac = 02:99:99:99:99:99,
ipv4_mtu = 1460,
policy_icmpv4_incoming = DROP,
policy_icmpv4_outgoing = DROP,
```

And here is its referred binding table:

```
psid_map {
    193.5.1.100 { psid_length=6, shift=10 }
}
br_addresses {
    fc00::100
}
softwires {
    { ipv4=193.5.1.100, psid=1, b4=fc00:1:2:3:4:5:0:7e }
    { ipv4=193.5.1.100, psid=2, b4=fc00:1:2:3:4:5:0:7f }
    { ipv4=193.5.1.100, psid=3, b4=fc00:1:2:3:4:5:0:80 }
    { ipv4=193.5.1.100, psid=4, b4=fc00:1:2:3:4:5:0:81 }
    ...
    { ipv4=193.5.1.100, psid=63, b4=fc00:1:2:3:4:5:0:bc }
}

```

Some of the lwAFTR's configuration fields are of special relevance for
SnabbVMX.  Although SnabbVMX can specify its own MTU and VLAN values, if those
attributes are also defined in a lwAFTR configuration file, the latter always
take precedence.

Please refer to Snabb's lwAFTR documentation for a detailed description about
lwAFTR's configuration file and binding table (Chapters 3 and 4).

## Configuration examples

### Dynamic next-hop resolution

```lua
return {
   lwaftr = "snabbvmx-lwaftr-xe0.conf",
   ipv6_interface = {
      cache_refresh_interval = 1,
      mtu = 9500,
   },
   ipv4_interface = {
      ipv4_address = "10.0.1.1",
      cache_refresh_interval = 1,
      mtu = 1460,
   },
}
```

Parameters:

- `ipv6_interface`: Configuration for lwAFTR's IPv6 interface (B4-side).
- `cache_refresh_interval`: Send next-hop resolution packet every second.
- `mtu`: Maximum Transfer Unit for IPv6 interface.


### Static next-hop resolution

```lua
return {
   lwaftr = "snabbvmx-lwaftr-xe0.conf",
   ipv6_interface = {
      mtu = 9500,
      next_hop_mac = "02:aa:aa:aa:aa:aa",
      fragmentation = false,
   },
   ipv4_interface = {
      ipv4_address = "10.0.1.1",
      next_hop_mac = "02:99:99:99:99:99",
      fragmentation = false,
      mtu = 9500,
   },
}
```

Parameters:

- `next_hop_mac`: MAC address of the nexthop.  Outgoing IPv4 or IPv6 packets
will use this MAC address as Ethernet destination address.
- `fragmentation`: Boolean field. Selects whether IPv4 or IPv6 packets get
fragmented by the lwAFTR in case packets are too big (larger than MTU size).

### Additional setup

```
return {
    ...
    settings = {
        vlan = 444,
        ingress_drop_monitor = 'flush',
        ingress_drop_threshhold = 100000,
        ingress_drop_wait = 15,
        ingress_drop_interval = 1e8,
    }
}
```

Parameters:

* `vlan`: Sets the same VLAN tag for IPv4 and IPv6.  If lwAFTR's configuration
defines VLAN tags, they take precedence.
* If `vlan_tag_v4` and `vlan_tag_v6` are defined in lwAFTR configuration, they
take precedence. In that case, **SplitV4V6** app is not needed and two virtual
interfaces are initialized instead, one for IPv4 and another one for IPv6,
each of them with its own VLAN tag.
* Ingress packet drop parameters initialize several features of the Snabb's
lwAFTR `ingress_drop_monitor` timer.  Periodically reports about the NIC
ingress packet drops. By default, ingress drop monitor is always run.
If not set, it takes the following default values:
    * `ingress_drop_monitor`: *flush*. Other possible values are *warn* for
warning and *off* for deactivating ingress drop monitoring.
    * `ingress_drop_threshold`: 100000 (packets).
    * `ingress_drop_interval`: 1e6 (1 second).
    * `ingress_drop_wait`: 20 (seconds).
