### LISPER (program.lisper)

Snabb Switch extension to support interfacing with an external control plane
for establishing L2TPv3 tunnels. The extension is suitable for use with
an external LISP (RFC 6830) controller.

#### Overview

![LISPER Use Case](.images/use_case.jpg)

In this diagram we have:

* LISP: the LISPER program.
* App: various applications that are connecting to LISPER.
* R2: an L3 router that connects everything together (could be one device
or e.g. the Internet).

The black lines are the physical connections: everything is connected
to the router. The green lines are the logical connections: the applications
are all connected to LISPER but not directly to each other. For the Apps
to talk with each other they send packets to LISPER that then forwards them
to the other Apps, according to a set of rules that the LISPER maintains
and that it receives from a LISP controller through a control socket.

##### LISPER

From this model we can imagine two different potential internal
structures for LISPER: a simple one targeting exactly this use case
or a more complex one that potentially handlers other use cases too.

![LISPER Connections - Simple Case](.images/lisper.jpg)

Here LISPER has its control socket and its "punt" interface and then a single
ethernet interface that connects to the router. The assumption here is that
we are always sending/receiving packets from one router and every packet
is L2TPv3 encapsulated. LISPER's job is to receive a packet, look at the
L2TPv3 header to see who is sending/receiving it, and then resend one
or more copies of it to the router for the destination(s) it should go to.

The more complex scenario would be to say that the LISP application is
connecting multiple Layer-2 networks together and each network can
be represented either by a physical network interface or a tunnel.
So we would support any number of network interfaces, both physical
and tunnels, and that each network could have any number of machines
on it.

![LISPER Connections - Complex Case](.images/lisper_ext.jpg)

##### Apps

What we call an "App" is really a machine running two layers of applications.
On top there is a virtual machine running a "legacy" networking application
that does _not_ know how to communicate over the internet/R2 and expects
to find other machines at the Ethernet level, and then below that
is our snabbnfv application that is configured to provide a transparent
point-to-point L2TPv3 tunnel that the virtual machine does not know about.

This allows deploying legacy apps inside virtual machines that require
being on the same LAN.

Here is a picture of this with QEMU VM on top and then snabbnfv process below:

![LISPER Apps](.images/apps.jpg)

Currently snabbnfv supports point-to-point tunnels between two endpoints.
So two VMs can connect to each other directly already. LISPER is needed
to create more complex topolgies that require connecting more than two
machines together.
