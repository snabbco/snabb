### NFV config (program.snabbnfv.nfvconfig)

The `program.snabbnfv.nfvconfig` module implements a [Network Functions
Virtualization](https://en.wikipedia.org/wiki/Network_Functions_Virtualization)
component based on Snabb. It introduces a simple configuration
file format to describe NFV configurations which it then compiles to app
networks. This NFV component is compatible with [OpenStack
Neutron](https://wiki.openstack.org/wiki/Neutron).

    DIAGRAM: NFV
    +------+
    |{d}   |
    | NFV  |         /---------\
    | conf |         | App     |
    +------+    /--->| network |
       |        |    \-=-------/
       :        :
       v        |
     +----------+-+
     |{io}        |
     | nfvconfig  |
     |            |
     +------------+

— Function **nfvconfig.load** *file*, *pci_address*, *socket_path*

Loads the NFV configuration from *file* and compiles an app network using
*pci_address* and *socket_path* for the underlying NIC driver and
`VhostUser` apps. Returns the resulting engine configuration.


#### NFV Configuration Format

The configuration file format understood by `program.snabbnfv.nfvconfig`
is based on *Lua expressions*. Initially, it contains a list of NFV
*ports*:

```
return { <port-1>, ..., <port-n> }
```

Each port is defined by a range of properties which correspond to the
configuration parameters of the underlying apps (NIC driver, `VhostUser`,
`PcapFilter`, `RateLimiter`, `nd_light` and `SimpleKeyedTunnel`):

```
port := { port_id        = <id>,          -- A unique string
          mac_address    = <mac-address>, -- MAC address as a string
          vlan           = <vlan-id>,     -- ..
          ingress_filter = <filter>,       -- A pcap-filter(7) expression
          egress_filter  = <filter>,       -- ..
          tunnel         = <tunnel-conf>,
          crypto         = <crypto-conf>,
          rx_police      = <n>,           -- Allowed input rate in Gbps
          tx_police      = <n> }          -- Allowed output rate in Gbps
```

The `tunnel` section deviates a little from `SimpleKeyedTunnel`'s
terminology:

```
tunnel := { type          = "L2TPv3",     -- The only type (for now)
            local_cookie  = <cookie>,     -- As for SimpleKeyedTunnel
            remote_cookie = <cookie>,     -- ..
            next_hop      = <ip-address>, -- Gateway IP
            local_ip      = <ip-address>, -- ~ `local_address'
            remote_ip     = <ip-address>, -- ~ `remote_address'
            session       = <32bit-int> } -- ~ `session_id'
```

The `crypto` section allows configuration of traffic encryption based on
`apps.ipsec.esp`:

```
crypto := { type          = "esp-aes-128-gcm", -- The only type (for now)
            spi           = <spi>,             -- As for apps.ipsec.esp
            transmit_key  = <key>,
            transmit_salt = <salt>,
            receive_key   = <key>,
            receive_salt  = <salt>,
            auditing      = <boolean> }
```


### snabbnfv traffic

The `snabbnfv traffic` program loads and runs a NFV configuration using
`program.snabbnfv.nfvconfig`. It can be invoked like so:

```
./snabb snabbnfv traffic <file> <pci-address> <socket-path>
```

`snabbnfv traffic` runs the loaded configuration indefinitely and
automatically reloads the configuration file if it changes (at most once
every second).

### snabbnfv neutron2snabb

The `snabbnfv neutron2snabb` program converts Neutron database CSV dumps
to the format used by `program.snabbnfv.nfvconfig`. For more info see
[Snabb NFV Architecture](doc/architecture.md).  It can be invoked like
so:

```
./snabb snabbnfv neutron2snabb <csv-directory> <output-directory> [<hostname>]
```

`snabbnfv neutron2snabb` reads the Neutron configuration *csv-directory*
and translates them to one `lib.nfv.conig` configuration file per
physical network. If *hostname* is given, it overrides the hostname
provided by `hostname(1)`.
