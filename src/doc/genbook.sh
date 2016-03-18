#!/usr/bin/env bash

# This shell scripts generates the top-level Markdown structure of the
# Snabb Switch book.
#
# The authors list is automatically generated from Git history,
# ordered from most to least commits.

# Link images in local .images/
for png in $(find .. -name "*.png"); do
    ln -f -s ../$png .images/
done

# Root directory for markdown files
mdroot=../obj

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

$(cat $mdroot/doc/in-a-nutshell.md)

## Core data structures

$(cat $mdroot/doc/core-data-structures.md)

# API

## Core modules

$(cat $mdroot/README.md)

## Traffic processing

$(cat $mdroot/lib/README.checksum.md)

$(cat $mdroot/lib/README.ctable.md)

## System programming

$(cat $mdroot/lib/hardware/README.md)

$(cat $mdroot/lib/watchdog/README.md)

$(cat $mdroot/lib/README.pmu.md)

## Protocol headers

$(cat $mdroot/lib/protocol/README.md)

# Apps

$(cat $mdroot/apps/basic/README.md)

## Hardware I/O

$(cat $mdroot/apps/intel/README.md)

$(cat $mdroot/apps/solarflare/README.md)

## Software I/O

$(cat $mdroot/apps/vhost/README.md)

$(cat $mdroot/apps/pcap/README.md)

$(cat $mdroot/apps/socket/README.md)

## Protocols

$(cat $mdroot/apps/ipv6/README.md)

$(cat $mdroot/apps/vpn/README.md)

## Traffic restriction

$(cat $mdroot/apps/rate_limiter/README.md)

$(cat $mdroot/apps/packet_filter/README.md)

# Programs

## NFV: optimized Virtio-net for QEMU

$(cat $mdroot/program/snabbnfv/README.md)

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
