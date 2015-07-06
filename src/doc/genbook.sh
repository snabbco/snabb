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

***Note:** This reference manual is a draft. The API defined in this
document is not guaranteed to be stable or complete and future versions
of Snabb Switch will introduce backwards incompatible changes. With that
being said, discrepancies between this document and the actual Snabb
Switch implementation are considered to be bugs. Please report them in
order to help improve this document.*

$(cat ../README.md)

$(cat ../apps/basic/README.md)

$(cat ../apps/intel/README.md)

$(cat ../apps/solarflare/README.md)

$(cat ../apps/rate_limiter/README.md)

$(cat ../apps/packet_filter/README.md)

$(cat ../apps/ipv6/README.md)

$(cat ../apps/vhost/README.md)

$(cat ../apps/pcap/README.md)

$(cat ../apps/vpn/README.md)

$(cat ../apps/socket/README.md)

# Libraries

## Hardware

$(cat ../lib/hardware/README.md)

## Protocols

$(cat ../lib/protocol/README.md)

## Snabb NFV

$(cat ../program/snabbnfv/README.md)

## Watchdog (lib.watchdog.watchdog)

$(cat ../lib/watchdog/README.md)

EOF
