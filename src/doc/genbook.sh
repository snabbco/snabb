#!/bin/sh

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

# Introduction

## Snabb in a nutshell
## Core software architecture
## Zen of Snabb

# API

## Core modules

$(cat ../README.md)

## Traffic processing

$(cat ../lib/README.checksum.md)

$(cat ../lib/README.ctable.md)

## System programming

$(cat ../lib/hardware/README.md)

$(cat ../lib/watchdog/README.md)

$(cat ../lib/README.pmu.md)

## Protocol headers

$(cat ../lib/protocol/README.md)

# Apps

$(cat ../apps/basic/README.md)

## Hardware I/O

$(cat ../apps/intel/README.md)

$(cat ../apps/solarflare/README.md)

## Software I/O

$(cat ../apps/vhost/README.md)

$(cat ../apps/pcap/README.md)

$(cat ../apps/socket/README.md)

## Protocols

$(cat ../apps/ipv6/README.md)

$(cat ../apps/vpn/README.md)

## Traffic restriction

$(cat ../apps/rate_limiter/README.md)

$(cat ../apps/packet_filter/README.md)

# Programs

## NFV: optimized Virtio-net for QEMU

$(cat ../program/snabbnfv/README.md)

## lwAFTR: lightweight 4-over-6
## ALX: Agile Lan eXtender (VPLS)
## Lisper: LISP dataplane
## packetblaster: "Infinite load" generator

# Development processs

## Git workflow

### Github repository
### Branches and upstreaming
### Making a contribution
### Continuous Integration
### Mailing list

## Snabb Lab

### Servers for community use
### NixOS server configuration
### Getting started

## Policies

### Apache license
### Copyright
### Trademarks
### Code of conduct

EOF
