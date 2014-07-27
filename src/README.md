# Snabb Switch App API v0.1

## `config`

A *config* is a description of a packet-processing network. The
network is a directed graph. Nodes in the graph are "apps" that each
process packets in a specific way -- switch, route, filter, police,
capture, etc. Each app has a set of named input and output "ports" --
for example called rx and tx. Edges in the graph are unidirectional
"links" that carry packets from an output port to an input port.

The config is a purely passive data structure. Creating and
manipulating a config object does not immediately affect operation.
The config has to be activated using `engine.configure(c)`.

* `config.new() => <config>` Create a new empty configuration.
* `config.app(c, name, class, arg)` Add an app to the config.  
  Example: `config.app(c, "nic", Intel82599, {pciaddr = "0000:00:00.0"})`
* `config.link(c, linkspec)` Add a link from an output port to an
  input port.  
  The *linkspec* is a string with syntax is
  `from_app.from_port->to_app.to_port`.  
  Example: `config.link(c,  "nic1.tx -> nic2.rx")`.

## `engine`

The *engine* executes a configuration by initializing apps, creating
links, and driving the flow of execution. The engine also performs
profiling and reporting functions. It can be reconfigured on-the-fly.

* `engine.configure(c)` Configure the engine to use a new configuration.
* `engine.main(options)` Execute the engine. Options:
    * `duration`: number of seconds to execute (a floating point number).
* `engine.report()` Print a report on current operational state.

## App

An *app* is the implementation of some specific networking function. For example, a switch, a router, or a packet filter.

Apps receive packets on "input ports", perform some processing, and transmit
packets on "output ports". Each app has zero or more input and output
ports. For example, a packet filter may have one input and one output
port, while a packet recorder may have only an input port.

* `myapp:new(arg)` Create an instance of the app with a given argument.
* `myapp.input` and `myapp.output` Tables of named input and output links.  
  These tables are initialized by the engine for use in processing.
* `myapp:pull()` Pull new work into the system. (Optional.)  
  For example: input packets from the network and transmit them to output ports.
* `myapp:push()` Push existing work through the system. (Optional.)  
  For example: move packets from input ports to output ports or onto an external network.
* `myapp:relink()` React to a change in input/output links.  
* Called after a link reconfiguration and before the next packets are processed.
* `myapp:reconfig(arg)` Reconfigure with a new arg. (Optional.): recreation of the app is used as a fallback.)
* `myapp:report()` Print a report of the current status.
* `myapp.zone` Name of the LuaJIT profiling zone for this app (a descriptive string). (Optional: module name used as a default.)

## `link`

A *link* is a [ring buffer](http://en.wikipedia.org/wiki/Circular_buffer)
containing packets. Links can be treated either like arrays --
accessing their internal structure directly -- or as streams of
packets via API functions.

* `link.empty(l)` Return true if the link is empty.
* `link.full(l)` Return true if the link is full.
* `link.receive(l)` Return the next available packet (and advance the read cursor). If the link is empty then an error is signaled.
* `link.front(l)` Return the next available packet without advancing the read cursor.  If the link is empty, `nil` is returned.
* `link.transmit(l, p)` Transmit a packet onto the link. If the link is full then the packet is dropped (and the drop counter increased).
* `link.stats(l)` Return a structure holding ring statistics:
    * `txbytes` and `rxbytes` count of transferred bytes.
    * `txpackets` and `rxpackets` count of transferred packets.
    * `txdrop` count of packes dropped due to ring overflow.

## `buffer`

A *buffer* is a block of memory containing packet data and suitable for DMA I/O.

* `buffer.allocate()` Return an uninitialized buffer.
* `buffer.free(b)` Free a buffer.  
  (This is usually done automatically when freeing a packet, see below.)
* `buffer.pointer(b)` Pointer to the underlying memory block (`char *`).
* `buffer.physical(b)` Physical address of the memory block for DMA (`uint64_t`).
* `buffer.size(b)` The size of the buffer in bytes (`uint32_t`).

## `packet`

A *packet* is a structure describing one of the network packets that
is currently being processed. The packet is used to access the payload
data, the metadata used during processing, and to explicitly manage
the lifecycle of the packet. Packets are explicitly reference-counted
at the application level instead of being garbage collected, because
there can be very many of them and they should be reused quickly.

* `packet.allocate()` return a new empty packet.
* `packet.add_iovec(p, buffer, length,  offset)` append packet data from a buffer.  
  The `offset` is optional and defaults to 0.
* `packet.niovecs(p)` Return the number of iovecs in the packet.
* `packet.iovec(p, n)` Return iovec `n` (starting from 0) of the packet.
* `packet.ref(p,  n)` Increase the reference count by `n` (default: 1).
* `packet.deref(p,  n)` Decrease the reference count by `n` (default: 1).  
  If the reference count reaches zero then the packet is automatically freed.
* `packet.tenure(p)` Give a packet "unlimited refs" so that `deref()` will have no effect.
* `packet.coalesce(p)` Merge all iovecs of a packet into one. (Deprecated)  
  This function is a temporary measure because not all parts of the code base have been made to support multiple iovecs.

## `timer`

A *timer* represents an action that should be taken at a specific time
in the future -- either repeatedly on a schedule or only once.

* `new(name, fn, nanos, mode)` Return a new timer object.
    * `name` descriptive string name.
    * `fn` function to call when the timer expires.
    * `nanos` how many nanoseconds in the future the timer will expire.
    * `mode` optionally the string `repeating` to expire repeatedly at `nanos` intervals.
* `activate(t)` Make a timer object active.

## `main`

The *main* module provides an interface for running snabbswitch scripts.

Scripts can be run either with:

    snabb ...snabb-args... <scriptfile> ...script-args...

or

    #!/usr/bin/env snabb ...snabb-args...
    ... lua code ...

* `main.parameters` list of command-line arguments for the running script.
* `main.exit(status)` orderly shutdown of the process.

