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

# Startup
## \`snabbswitch.c\`: C \`main()\` entry point
$(cat obj/snabbswitch.c.md)
## \`main.lua\`: Lua entry point
$(cat obj/main.lua.md)
## \`snabb_lib_init.c\`: Customized Lua initialization
$(cat obj/snabb_lib_init.c.md)

# Hardware interface
## \`register.lua\`: Hardware device register abstraction
$(cat obj/register.lua.md)
## \`intel.h\`: Data structures for DMA
$(cat obj/intel.h.md)
## \`intel10g.lua\`: Intel 10-Gigabit device driver
$(cat obj/intel10g.lua.md)
## \`intel.lua\`: Intel Gigabit device driver
$(cat obj/intel.lua.md)

# Linux interface
## \`memory.lua\`: Physical memory management
$(cat obj/memory.lua.md)
## \`pci.lua\`: PCI device access (via sysfs)
$(cat obj/pci.lua.md)
## \`snabb.h\`: C support API
$(cat obj/snabb.h.md)
## \`snabb.c\`: C support library code
$(cat obj/snabb.c.md)

# Networking logic
## \`port.lua\`: Ethernet network port
$(cat obj/port.lua.md)
## \`buffer.lua\`: Network packet buffer
$(cat obj/buffer.lua.md)

# Library
## \`clib.h\`: Standard C function prototypes
$(cat obj/clib.h.md)
## \`lib.lua\`: Lua library routines
$(cat obj/lib.lua.md)

EOF
