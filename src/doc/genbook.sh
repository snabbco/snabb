#!/bin/bash

# This shell scripts generates the top-level Markdown structure of the
# Snabb Switch book.
#
# The authors list is automatically generated from Git history,
# ordered from most to least commits.

# Link images in local .images/
for png in $(find .. -name "*.png"); do
    ln -s ../$png .images/
done

cat <<EOF
% Snabb Switch Reference Manual
% $(git log --pretty=format:%an | \
        grep -v -e '^root$' | \
        sort | uniq -c | sort -nr | sed 's/^[0-9 ]*//' | \
        awk 'BEGIN     { first=1; }
             (NF >= 2) { if (first) { first=0 } else { printf("; ") };
                         printf("%s", $0) }
             END { print("") }')
% Version $(git log -n1 --format="format:%h, %ad%n")

$(cat ../README.md)

$(cat ../apps/README.md)

$(cat ../apps/intel/README.md)

$(cat ../apps/rate_limiter/README.md)

$(cat ../apps/packet_filter/README.md)

# Operating System and Hardware Integration

## Memory Management

$(cat memory.md)

## Virtio (Bridge to Virtualized Guests)

$(cat virtio.md)

# Extra Modules, Designs and Scripts

## \`lib.watchdog\`: Process Watchdog

$(cat ../lib/watchdog/README.md)

EOF
