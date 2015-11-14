# Overview

This directory contains scripts for creating a self-contained
development enviornment for the LISPER project.

To create the environment, type (as root):

    ./net-bringup

When finished, type:

    ./net-teardown

# What does it do?

It creates a virtual network of 3 machines in 3 different subnets
connected to a router. Besides that, app1 and app2 machines create
two static l2tp tunnels which connect _to the same endpoint_ in the
lisp machine where lisper responds back.

# Implementation

The network nodes are created using Linux network namespaces.

The L2TPv3 endpoints are maintained with a Lua script which
does the L2TPv3 decap/encap'ing and forwarding packets between
the tunneled interface (which is a TAP) and the transport
interface (which is a veth interface opened in raw mode).

There's also a LISP controller mock-up program which pushes
config data to LISPER continuously every second.
