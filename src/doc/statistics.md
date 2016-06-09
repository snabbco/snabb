### Statistics counters in Snabb

Below is list of statistics counters defined by Snabb, and their relation to
RFC 7223 and ifTable MIB. All counters are unsigned 64bit integers. Each Snabb
app can optionally implement any number of these counters.

| Snabb                        | RFC 7223                     | ifTable MIB
| -----                        | --------                     | -----------
|                              | name                         |
|                              | description?                 | ifDescr
| type (~= identity)           | type                         | ifType
|                              | enabled?                     |
|                              | link-up-down-trap-enable?    |
|                              | admin-status                 |
| status (= enum)              | oper-status                  | ifOperStatus
|                              | last-change?                 | ifLastChange
|                              | if-index                     |
| macaddr (uint64)             | phys-address?                | ifPhysAddress
|                              | higher-layer-if*             |
|                              | lower-layer-if*              |
| speed                        | speed?                       | ifSpeed
| dtime (seconds since epoch)  | discontinuity-time           | ifCounterDiscontinuityTime
| rxbytes                      | in-octets?                   | ifInOctets
| rxpackets                    |                              |
|                              | in-unicast-pkts?             |
| rxbcast                      | in-broadcast-pkts?           | ifInBroadcastPkts
| rxmcast                      |                              |
|                              | in-multicast-pkts?           | ifInMulticastPkts
| rxdrop                       | in-discards?                 | ifInDiscards
| rxerrors                     | in-errors?                   | ifInErrors
|                              | in-unknown-protos?           |
| txbytes                      | out-octets?                  | ifOutOctets
| txpackets                    |                              |
|                              | out-unicast-pkts?            |
| txbcast                      | out-broadcast-pkts?          | ifOutBroadcastPkts
| txmcast                      |                              |
|                              | out-multicast-pkts?          | ifOutMulticastPkts
| txdrop                       | out-discards?                | ifOutDiscards
| txerrors                     | out-errors?                  | ifOutErrors
| mtu                          |                              | ifMtu
| promisc                      |                              | ifPromiscuousMode


#### type

 - `0x1000` Hardware interface
 - `0x1001` Virtual interface

#### rxbcast, rxmcast, rxpackets, txbcast, txmcast, txpackets

Snabb defines total packet counts, multicast packet counts (packets with group
bit set) and broadcast packet counts for both input and output.

   E.g.: (tx/rx)bcast ⊆ (tx/rx)mcast ⊆ (tx/rx)packets
