# Snabbswitch instance variables
SNAB="src/snabbswitch/src/snabbswitch"
NFV="src/snabbswitch/src/designs/nfv/nfv"
LOADGEN="src/snabbswitch/src/designs/loadgen/loadgen"
PCAP="var/http.cap"

NODE_BIND0="0"
SNAB_LOG0="/dev/null"
NFV_PCI0="0000:07:00.0"
NFV_SOCKET0="vhost$$_0.sock"

NODE_BIND1="1"
SNAB_LOG1="/dev/null"
NFV_PCI1="0000:84:00.0"
NFV_SOCKET1="vhost$$_1.sock"

# QEMU
GUEST_MEM="512"
HUGETLBFS="/hugetlbfs"
KERNEL="vm/bzImage-trusty"
QEMU="src/qemu/obj/x86_64-softmmu/qemu-system-x86_64"

# Guest instance #0
TAP0="tap0"
TELNET_PORT0="5000"
GUEST_IP0="192.168.2.10"
GUEST_MAC0="52:54:00:00:00:00"
IMAGE0="vm/ubuntu-trusty-pass-asdf.img0"
BOOTARGS0="earlyprintk root=/dev/vda rw console=ttyS0 ip=$GUEST_IP0"

# Guest instance #1
TAP1="tap1"
TELNET_PORT1="5001"
GUEST_IP1="192.168.2.11"
GUEST_MAC1="52:54:00:00:00:01"
IMAGE1="vm/ubuntu-trusty-pass-asdf.img1"
BOOTARGS1="earlyprintk root=/dev/vda rw console=ttyS0 ip=$GUEST_IP1"

