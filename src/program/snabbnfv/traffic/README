snabbnfv traffic [OPTIONS] <pci-address> <config-file> <socket-path>

  -k SECONDS, --link-report-interval SECONDS
                             Print an link status report every SECONDS.
			     Default: 60s
  -l SECONDS, --load-report-interval SECONDS
                             Print a processing load report every SECONDS.
			     Default: 1s
  -D SECONDS, --debug-report-interval SECONDS
                             Print a debug report every SECONDS.
			     The debug report includes a NIC register dump.
			     Default: 600s (10 minutes)
  -b, --busy                 Run in a busy-loop without sleeping.
                             This minimizes latency but consumes 100% CPU.
  -B NPACKETS, --benchmark NPACKETS
                             Benchmark processing NPACKETS.
  -h, --help
                             Print brief command-line usage information.
  -H, --long-help
                             Print long usage information including
                             configuration file format.

Process traffic between Neutron ports and a physical NIC.

In benchmark mode, measure the throughput for the first <npackets> and
then report and terminate.

CONFIG FILE FORMAT:

  <config-file> contains a list of all of the virtual machine ports. The
  file is in Lua source format and returns an array of ports:

      return { <port-1>, ..., <port-n> }

  Each port is defined by a range of properties which correspond to the
  configuration parameters of the underlying apps (NIC driver, VhostUser,
  PcapFilter, RateLimiter, nd_light and SimpleKeyedTunnel):

      port := { port_id        = <id>,          -- A unique string
                mac_address    = <mac-address>, -- MAC address as a string
                vlan           = <vlan-id>,     -- ..
                ingress_filter = <rules>,       -- A pcap-filter(7) expression
                egress_filter  = <rules>,       -- ..
                tunnel         = <tunnel-conf>,
                crypto         = <crypto-conf>,
                rx_police      = <n>,           -- Allowed input rate in Gbps
                tx_police      = <n> }          -- Allowed output rate in Gbps

  The tunnel section deviates a little from SimpleKeyedTunnel's
  terminology:

      tunnel := { type          = "L2TPv3",     -- The only type (for now)
                  local_cookie  = <cookie>,     -- As for SimpleKeyedTunnel
                  remote_cookie = <cookie>,     -- ..
                  next_hop      = <ip-address>, -- Gateway IP
                  local_ip      = <ip-address>, -- ~ `local_address'
                  remote_ip     = <ip-address>, -- ~ `remote_address'
                  session       = <32bit-int>   -- ~ `session_id' }

  The crypto section allows configuration of traffic encryption based on
  apps.ipsec.esp:

      crypto := { type          = "esp-aes-128-gcm", -- The only type (for now)
                  spi           = <spi>,             -- As for apps.ipsec.esp
                  transmit_key  = <key>,
                  transmit_salt = <salt>,
                  receive_key   = <key>,
                  receive_salt  = <salt>,
                  auditing      = <boolean> }
