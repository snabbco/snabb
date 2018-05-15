# Inter-process links (apps.interlink.*)

The “interlink” transmitter and receiver apps allow for efficient exchange
of packets between Snabb processes within the same process group (see
[Multiprocess operation (core.worker)](#multiprocess-operation-core.worker)).

    DIAGRAM: Transmitter and Receiver
           +-------------+  +-------------+
           |             |  |             |
    input  |             |  |             |
       ----* Transmitter |  |   Reciever  *----
           |             |  |             |  output
           |             |  |             |
           +-------------+  +-------------+

To make packets from an output port available to other processes, configure a
transmitter app, and link the appropriate output port to its `input` port.

```lua
local Transmitter = require("apps.interlink.transmitter")

config.app(c, "interlink", Transmitter)
config.link(c, "myapp.output -> interlink.input")
```

Then, in the process that should receive the packets, configure a receiver app
with the same name, and link its `output` port as suitable.

```lua
local Receiver = require("apps.interlink.receiver")

config.app(c, "interlink", Receiver)
config.link(c, "interlink.output -> otherapp.input")
```

Subsequently, packets transmitted to the transmitter’s `input` port will appear
on the receiver’s `output` port.

## Configuration

None, but the configured app names are globally unique within the process
group.

Starting either the transmitter or receiver app attaches them to a shared
packet queue visible to the process group under the name that was given to the
app. When the queue identified by the name is unavailable, because it is
already in use by a pair of processes within the group, configuration of the
app network will block until the queue becomes available. Once the transmitter
or receiver apps are stopped they detach from the queue.

Only two processes (one receiver and one transmitter) can be attached to an
interlink queue at the same time, but during the lifetime of the queue (e.g.,
from when the first process attached to when the last process detaches) it can
be shared by any number of receivers and transmitters. Meaning, either process
attached to the queue can be restarted or replaced by another process without
packet loss.
