# Use of this source code is governed by the Apache 2.0 license; see COPYING.
#!/usr/bin/env bash

# Example and test environment for Snabb lwAFTR
#
# Use with: lwaftr-start.conf
#
# This script creates two network namespaces, 'aftrint' and 'aftrext',
# that simulate the external network (public internet) and the internal,
# IPv6-only network (operator network) respectively.
#
# Snabb lwAFTR sits between the two networks and routes packets between
# the external IPv4 network and the internal IPv6-only network.
#
# In the external network is a node with the public address: 10.77.0.10
# In the internal network is a node with the private address: 198.18.0.1
# In the internal network flows towards 198.18.0.1 are encapsulated in IPv6,
# and the IPv4 address is mapped to 2003:1c09:ffe0:100::1.
#
# The address of Snabb lwAFTR in the external network is 10.77.0.1 and
# its address in the internal network is fd10::1.

set -e

create() { set -x
    # Create two veth pairs for the internal and external Snabb lwAFTR interfaces

    ip link add aftrv6 type veth peer name internal
    ip link set aftrv6 address 02:00:00:00:00:02 # lwAFTR internal-interface/mac
    ip link set aftrv6 up

    ip link add aftrv4 type veth peer name external
    ip link set aftrv4 address 02:00:00:00:00:01 # lwAFTR external-interface/mac
    ip link set aftrv4 up

    # Configure internal network namespace

    ip netns add aftrint
    ip netns exec aftrint ip link set lo up
    ip link set internal netns aftrint

    # Configure internal interface

    ip netns exec aftrint ethtool --offload internal  rx off tx off
    ip netns exec aftrint ip address add dev internal local fd10::10/16 # lwAFTR internal-interface/next-hop
    ip netns exec aftrint ip link set internal mtu 1540 # lwAFTR internal-interface/mtu
    ip netns exec aftrint ip link set internal up
    sleep 3
    # Default route to lwAFTR
    ip netns exec aftrint ip route add default via fd10::1 dev internal

    # Configure external network namespace

    ip netns add aftrext
    ip netns exec aftrext ip link set lo up
    ip link set external netns aftrext

    # Configure external interface

    ip netns exec aftrext ethtool --offload external  rx off tx off
    ip netns exec aftrext ip address add dev external local 10.77.0.10/24 # lwAFTR external-interface/next-hop
    ip netns exec aftrext ip link set external mtu 1500 # lwAFTR external-interface/mtu
    ip netns exec aftrext ip link set external up
    sleep 3
    # Route to 198.18.0.0/16 (internal v4 nodes) via lwAFTR
    ip netns exec aftrext ip route add 198.18.0.0/16 via 10.77.0.1 src 10.77.0.10 dev external
    # Default route to lwAFTR
    ip netns exec aftrext ip route add default via 10.77.0.1 dev external 

    # Configure tunneled endpoint in the internal network namespace
    # 
    # Here we configure the softwire as defined in the binding table entry in
    # lwaftr-start.conf
    #
    #   softwire {
    #     ipv4 198.18.0.1;
    #     psid 0;
    #     b4-ipv6 2003:1c09:ffe0:100::1;
    #     br-address 2003:1b0b:fff9:ffff::4001;
    #     port-set {
    #       psid-length 0;
    #     }
    #   }
    #
    # Note how ipv4, b4-ipv6, br-address relate to the Linux ip-tunnel and
    # ip-route configuration.

    ip netns exec aftrint ip address add dev internal local 2003:1c09:ffe0:100::1 # b4-ipv6
    ip netns exec aftrint ip address add dev internal local 198.18.0.1/16 # ipv4
    # Here we create the ip-tunnel counterpart to our softwire
    # between br-address and b4-ipv6.
    ip netns exec aftrint ip -6 tunnel add name softwire0 \
        remote 2003:1b0b:fff9:ffff::4001 local 2003:1c09:ffe0:100::1 \
        mode ipip6 encaplimit none dev internal
    ip netns exec aftrint ip link set softwire0 up
    # Route from internal endpoint (ipv4) to public network (10.77.0.0/16) via softwire
    ip netns exec aftrint ip route add 10.77.0.0/16 src 198.18.0.1 dev softwire0
    # Route to br-address via lwAFTR
    ip netns exec aftrint ip route add 2003::0/16 via fd10::1 src fd10::10 dev internal
}

destroy() { set -x
    # Delete the network namespaces and the attached veth pairs
    ip netns delete aftrint || true
    ip link delete aftrv6 || true
    ip netns delete aftrext || true
    ip link delete aftrv4 || true
}

if [ "$1" = "create" ]; then
    create
elif [ "$1" = "destroy" ]; then
    destroy
elif [ "$1" = "examples" ]; then
    cat <<EOF

Run Snabb lwAFTR on aftrint/internal and aftrext/external:
  sudo src/snabb lwaftr run --name testaftr --conf src/program/lwaftr/doc/tutorial/lwaftr-start.conf &

Ping Snabb lwAFTR instance from aftrint/internal:
  sudo ip netns exec aftrint ping -c 1 fd10::1 

Ping Snabb lwAFTR instance from aftrext/external:
  sudo ip netns exec aftrext ping -c 1 10.77.0.1

Display traffic on internal or external interfaces:
  sudo ip netns exec aftrint tcpdump -nn -i internal -l --immediate-mode &
  sudo ip netns exec aftrext tcpdump -nn -i external -l --immediate-mode &

Ping from internal to external endpoint:
  sudo ip netns exec aftrint ping -c 1 10.77.0.10

Ping from external to internal endpoint:
  sudo ip netns exec aftrext ping -c 1 198.18.0.1

EOF
else
    echo "Usage: sudo lwaftr-veth-env.sh create|destroy|examples"
fi

