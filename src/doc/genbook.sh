#!/usr/bin/env bash

# This shell scripts generates the top-level Markdown structure of the
# Snabb book.
#
# The authors list is automatically generated from Git history,
# ordered from most to least commits.

# Root directory for markdown files
mdroot=../obj

# Link images in local .images/
for png in $(find .. -name "*.png"); do
    ln -s ../../$png $mdroot/doc/.images/
done

cat <<EOF
% Snabb Reference Manual
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
of Snabb will introduce backwards incompatible changes. With that
being said, discrepancies between this document and the actual Snabb
Switch implementation are considered to be bugs. Please report them in
order to help improve this document.*

$(cat $mdroot/README.md)

$(cat $mdroot/apps/basic/README.md)

$(cat $mdroot/apps/intel/README.md)

$(cat $mdroot/apps/intel_mp/README.md)

$(cat $mdroot/apps/solarflare/README.md)

$(cat $mdroot/apps/rate_limiter/README.md)

$(cat $mdroot/apps/packet_filter/README.md)

$(cat $mdroot/apps/ipv4/README.md)

$(cat $mdroot/apps/ipv6/README.md)

$(cat $mdroot/apps/vhost/README.md)

$(cat $mdroot/apps/virtio_net/README.md)

$(cat $mdroot/apps/pcap/README.md)

$(cat $mdroot/apps/vpn/README.md)

$(cat $mdroot/apps/socket/README.md)

$(cat $mdroot/apps/tap/README.md)

$(cat $mdroot/apps/vlan/README.md)

$(cat $mdroot/apps/bridge/README.md)

$(cat $mdroot/apps/ipfix/README.md)

$(cat $mdroot/apps/ipsec/README.md)

$(cat $mdroot/apps/test/README.md)

$(cat $mdroot/apps/wall/README.md)

$(cat $mdroot/apps/rss/README.md)

$(cat $mdroot/apps/interlink/README.md)

# Libraries

$(cat $mdroot/lib/README.checksum.md)

$(cat $mdroot/lib/README.ctable.md)

$(cat $mdroot/lib/README.poptrie.md)

$(cat $mdroot/lib/README.pmu.md)

$(cat $mdroot/lib/yang/README.md)

## Hardware

$(cat $mdroot/lib/hardware/README.md)

## Protocols

$(cat $mdroot/lib/protocol/README.md)

## IPsec

$(cat $mdroot/lib/ipsec/README.md)

## Snabb NFV

$(cat $mdroot/program/snabbnfv/README.md)

## LISPER

$(cat $mdroot/program/lisper/README.md)

## Ptree

$(cat $mdroot/program/ptree/README.md)

## Watchdog (lib.watchdog.watchdog)

$(cat $mdroot/lib/watchdog/README.md)

# Snabblab

$(cat $mdroot/doc/snabblab.md)

EOF
