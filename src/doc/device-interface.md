
new(args)
----

Create and start a network device interface

stop()
----

Stop a network device interface

set_rx_buffer_freelist(fl)
----

Set receive buffer freelist for special purpose applications
(testing/loopback).  Normally allocated by add_receive_buffers.

add_receive_buffers()
----

Allocate receive buffers in hardware to prepare it for receiption of
packets.

push()
----

Take packets off the internal input link and put them to the hardware
for sending until either no more packets are to be transmitted or the
output queue is full.

pull()
----

Take packets off the hardware input queue and put them onto the
internal output link until either the internal link is full or no more
packets are on the input queue.

report()
----

Report device status and statistics to the standard output.

selftest()
----

Perform a device self test.
