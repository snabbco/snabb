#!/bin/bash

# This shell scripts generates the top-level Markdown structure of the
# Snabb Switch book.
#
# The authors list is automatically generated from Git history,
# ordered from most to least commits.

cat <<EOF
% Snabb Switch
% $(git log --pretty=format:%an | \
        grep -v -e '^root$' | \
        sort | uniq -c | sort -nr | sed 's/^[0-9 ]*//' | \
        awk 'NR > 1 { printf("; ") } { printf("%s", $0) } END { print("") }')

# Memory
$(cat memory.md)
## \`memory.c\`: Operating system support
$(cat obj/memory.c.md)
## \`memory.lua\`: Allocate physical memory in Lua
$(cat obj/memory.lua.md)
## \`buffer.lua\`: Allocate packet buffers from a pool
$(cat obj/buffer.lua.md)

# PCI
## \`pci.c\`: Operating system support
$(cat obj/pci.c.md)
## \`pci.lua\`: PCI access in Lua
$(cat obj/pci.lua.md)

# Hardware ethernet I/O
## Hardware device register access
$(cat obj/register.lua.md)
## Intel 82599 (10-Gigabit) ethernet device driver
$(cat obj/intel10g.lua.md)

# Software ethernet I/O (virtio)
$(cat virtio.md)
## \`virtio_vring.h\`: vring DMA ring buffer data structure
$(cat obj/virtio_vring.h.md)
## \`virtio_vhost.h\`: vhost Linux kernel `ioctl` data structures
$(cat obj/virtio_vhost.h.md)
## \`virtio_vhost_client.c\`: Linux \`/dev/vhost-net\` vhost client
$(cat obj/virtio_vhost_client.c.md)
## \`virtio.lua\`: virtio network device driver
$(cat obj/virtio.lua.md)

$(cat kvm.md)

# *DRAFT* Networking
## \`port.lua\`: Ethernet network port
$(cat obj/port.lua.md)
## \`hub2.lua\`: 2-port ethernet hub
$(cat obj/hub2.lua.md)

$(cat openstack.md)

# *DRAFT* Library
## \`clib.h\`: Standard C function prototypes
$(cat obj/clib.h.md)
## \`lib.lua\`: Lua library routines
$(cat obj/lib.lua.md)

# Startup
## \`snabbswitch.c\`: C \`main()\` entry point
$(cat obj/snabbswitch.c.md)
## \`main.lua\`: Lua entry point
$(cat obj/main.lua.md)
## \`snabb_lib_init.c\`: Customized Lua initialization
$(cat obj/snabb_lib_init.c.md)

EOF
