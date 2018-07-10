Usage: lwaftr --help

run --conf <config-file> --id <port-id> --pci <pci-addr> --mac <mac-address> \
    --sock <socket-path> [-D <seconds>] [-v]

Arguments:

  --conf    <config-file>   configuration file for lwaftr service
  --id      <port-id>       port_id for virtio socket
  --pci     <pci-addr>      PCI device number for NIC (or Linux interface name)
  --mac     <mac address>   Ethernet address of virtio interface
  --sock    <socket-path>   Socket path for virtio-user interfaces

Optional:

  -D        <seconds>       Duration in seconds
  -v                        Verbose (repeat for more verbosity)

Example config file:

# cat snabbvmx-lwaftr-xe0.cfg
return {
   lwaftr = "snabbvmx-lwaftr-xe0.conf",
   ipv6_interface = {
     cache_refresh_interval = 1,
   },
   ipv4_interface = {
     ipv4_address = "10.0.1.1",
     cache_refresh_interval = 1,
   },
   settings = {},
}

and the referenced 'lwaftr.conf' file:

# cat lwaftr.conf
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
