# Overview

This directory contains scripts for creating a self-contained
development enviornment for the LISPER project.

The goal is to create a dev environment that reproduces the whole
use-case network (the first diagram in the Overview section of the
LISPER documentation) in software using only network namespaces
and virtual interfaces.

To create the environment, type (as root):

    ./net-bringup

When finished, type:

    ./net-teardown

While the network is up, you can access a virtual L2 network of 3 "machines"
which you can shell-in by typing `./nsapp1`, `./nsapp2` and `./nsapp3`
respectively. For each machine, `ifconfig` shows an interface with
a different IP in the `10.0.0.0/24` subnet. These IPs should be able
to ping each other.

# How does it work?

A virtual network is created of 3 machines in 3 different subnets,
all connected to a fourth one acting as a router between them (this is done
using network namespaces, there are no actual virtual machines).
There are 4 namespaces in total named `app1`, `app2`, `app3`, `lisp`, and `r2`.

The namespaces are connected through veth interfaces whose end-points are:

   r2.e1 <-> app1.e0
   r2.e2 <-> app2.e0
   r2.e3 <-> app3.e0
   r2.e4 <-> lisp.e0

An instance of `l2tp.lua` runs on each `appN` namespace. Its job is to expose
a TAP interface `appN.t0`. Ethernet frames coming into `appN.t0` are
L2TPv3-encapsulated and sent out to `lisp.e0` through `appN.e0`
(and viceversa: L2TPv3-encapsulated packets coming into `appN.e0` are
decapsulated and sent to `appN.t0`).

An instance of `snabb/src/program/lisper/lisper.lua` runs on the `lisp`
namespace. Its job is to route L2TPv3-encapsulated packets coming into
`lisp.e0` from `appA.e0` to `appB.e0` based on a MAC->IP mapping called FIB.

An instance of `lisp.lua` also runs on the `lisp` namespace.
This is a mockup of a LISP controller. All it does right now is sending
the contents of the `lisp.fib` file to the lisper program every second.

# Why does it work?

A L2 frame sent into `app1.t0` destined to `app2.t0` travels like this:

`app1.t0` -> (L2TPv3-encap by `l2tp.lua`) ->
`app1.e0` -> (veth bridging) ->
`r2.e1`   -> (IPv6 routing by Linux kernel) ->
`r2.e4`   -> (veth bridging) ->
`lisp.e0` -> (L2TPv3 routing by `lisper.lua`) ->
`lisp.e0` -> (veth bridging) ->
`r2.e4`   -> (IPv6 routing by Linux kernel) ->
`r2.e2`   -> (veth bridging) ->
`app2.e0` -> (L2TPv3-decap by `l2tp.lua`) ->
`app2.t0`

