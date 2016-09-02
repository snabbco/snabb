# Snabb Getting Started Guide

## Introduction

Welcome to Snabb, a software switch for the NFV world! The purpose
of this guide is to introduce end users and developers to how to use
Snabb. We'll delve into several aspects of Snabb Switch at a high
level prior to implementing an example network function using the Snabb
Switch concept of an *App*.

## Prerequisites

Running the code in this guide requires a recent distribution of
Linux. The examples were written on a fresh install of a 64-bit Ubuntu
14.04 distribution on an IaaS virtual machine. There is no requirement
for a hardware NIC supported by Snabb for these examples.

## Downloading, Compiling, and Installing Snabb

The following commands clone the Snabb repository, compile the
software, and install the `snabb` executable. Note that the output of the
commands is omitted.

```
sudo apt-get update
sudo apt-get -y install build-essential git
git clone https://github.com/snabbco/snabb.git
cd snabb
make -j
```

## Your First Snabb Program

Snabb provides you with many reusable network components out of
the box. In Snabb terminology we call these components *Apps*,
because they perform a specific function and can be combined with each
other in arbitrary ways. In this guide we will use two of the apps
bundled with Snabb to build a small but useful tool.

1. [PcapReader](../apps/pcap/README.md) - This app reads packets from a
PCAP capture file.
2. [RawSocket](../apps/socket/README.md) - This app receives and
transmits packets over Linux network interfaces.

Each app can receive packets from an arbitrary number of *input links*
and transmit packets to an arbitrary number of *output links*. Snabb
Switch provides you with a little language to link together apps in a
directed graph that governs the packet flow. We call this graph an *App
network*. In our first example the output of `PcapReader` will be sent to
the input of `RawSocket`.

Our example will implement a packet replay program that reads a PCAP file
and then plays back the packets to an arbitrary Ethernet interface.

You can find the `example_replay.lua` program in the
`src/program/example_replay` directory. Let us go over it and explain it
step by step:

```
module(..., package.seeall)

local pcap = require("apps.pcap.pcap")
local raw = require("apps.socket.raw")
```

The first line contains a call to `module`, its a Lua specific function
that creates a loadable module for the code defined in this file. Then we
use `require` to load other modules we want to use: `apps.pcap.pcap` and
`apps.socket.raw`.

```
function run (parameters)
   if not (#parameters == 2) then
      print("Usage: example_replay <pcap-file> <interface>")
      main.exit(1)
   end
   local pcap_file = parameters[1]
   local interface = parameters[2]
```

Snabb treats modules under `src/program` specially: if a module
exposes a top-level `run` function it can be invoked from the `snabb`
executable. E.g. to execute `run` you would invoke `snabb` like so:

`src/snabb example_replay <args...>`

Since this is a command line program we need to verify and parse the
arguments we want to accept. The first argument to `run` will be an array
containing the command line arguments. In this program we require two
arguments, namely the PCAP file and interface to use.

```
   local c = config.new()
   config.app(c, "capture", pcap.PcapReader, pcap_file)
   config.app(c, "playback", raw.RawSocket, interface)

   config.link(c, "capture.output -> playback.rx")
```

Now we get to the meat of this program: building the app network. First
we get ourselves an an empty configuration `c` by calling
`config.new`. We then add two app instances to our nework by calling
`config.app` on our configuration:

* `capture` - an instance of the `PcapReader` app which will read
  `pcap_file`
* `playback` - an instance of the `RawSocket` app that will receive from
  and transmit to `interface`

Then we use `config.link` to define a connection between our apps:
`capture` will transmit packets from its `output` port to `playback`'s
`rx` port. Since `capture` is a `PcapReader` it will transmit packets
from a PCAP capture file to its `output` port. `playback` is a
`RawSocket` and thus will transfer packets received on the `rx` port to
the interface. In case you are curious, we could receive incoming packets
from `playback`'s underlying network interface by connecting its `tx`
port to another app, e.g. a [PcapWriter](../apps/pcap/README.md) app.

```
   engine.configure(c)
   engine.main({duration=1, report = {showlinks=true}})
end
```

Finally we will load our configuration `c` into the engine by calling
`engine.configure`. Now we can run our app network by calling
`engine.main`. In this example run it for one second, naively assuming
that will be more than enough time for the PCAP file to be processed.


## Running The `example_replay` Program

We'll use a virtual interface as testing yields strange results when the
sample program runs on "real" network interfaces in some IaaS
environments. If you run the program in a controlled environment, you
should be able to use `eth0` or any other network interface without
problems.

Create the `veth` pair using the following commands:

```
sudo ip link add veth0 type veth peer name veth1
sudo ip link set dev veth0 up
sudo ip link set dev veth1 up
```

An `input.pcap` file is included in the `src/program/example_replay`
directory but you can just as well use any other PCAP file.

Open a second terminal window and run `tcpdump` on `veth0`:

```
sudo tcpdump -i veth0
```

From Snabb directory, run the following invocation of our example
program:

```
sudo src/snabb example_replay src/program/example_replay/input.pcap veth0
```

You should see the following output:

```
link report:
                   5 sent on capture.output -> playback.rx (loss rate: 0%)
```

In your other window, `tcpdump` will capture the outbound packets on
`veth0`:

```
tcpdump: WARNING: veth0: no IPv4 address assigned
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on veth0, link-type EN10MB (Ethernet), capture size 65535 bytes
17:45:34.097183 IP 10.0.0.1 > 10.0.0.2: ICMP echo request, id 2320, seq 1, length 64
17:45:34.097228 IP 10.0.0.1 > 10.0.0.2: ICMP echo request, id 2320, seq 2, length 64
17:45:34.097242 IP 10.0.0.1 > 10.0.0.2: ICMP echo request, id 2320, seq 3, length 64
17:45:34.097254 IP 10.0.0.1 > 10.0.0.2: ICMP echo request, id 2320, seq 4, length 64
17:45:34.097268 IP 10.0.0.1 > 10.0.0.2: ICMP echo request, id 2320, seq 5, length 64
^C
5 packets captured
5 packets received by filter
0 packets dropped by kernel
```

Congratulations! You have successfully run your first Snabb
program.

## Your First Snabb App

The example program described above configures an app network using apps
already included with Snabb. But writing custom Snabb Switch apps
its easy. Let's inspect an example app to get you going!

Our forwarding logic for the app will be simple (and silly): the app
will send every other packet on its output port. The odd numbered
packets will be silently discarded. While this is not useful, the
purpose is to show the anatomy of a Snabb *app*.

Snabb apps are required to implement one method: new. The `new`
method returns an instance of your app. An optional method we'll use is
`push`, which moves packets from the input to output ports. Let's examine
the example app defined in `src/program/example_spray/sprayer.lua`.

```lua
module(..., package.seeall)

Sprayer = {}
```

Again we use `module` to declare a module. Then we create an empty
`Sprayer` table to define some methods on.

```
function Sprayer:new ()
   local o = { packet_counter = 1 }
   return setmetatable(o, {__index = Sprayer})
end
```

This is the `new` method of our app. It returns an instance of `Sprayer`
with a `packet_counter` field initialized to 1. We will use the counter
to determine which packet to drop.

```
function Sprayer:push()
   local i = assert(self.input.input, "input port not found")
   local o = assert(self.output.output, "output port not found")
```

The `push` method of our app will be called by the engine to pump packets
through the app network. First of all we get a hold of the ports we want
to receive and transmit packets on, `i` and `o`. For each app instance
`self.input` and `self.output` will be bound to tables mapping port names
to the underlying *link* data structures. We assert that the links
actually exists in order to raise an exception immediately if the app was
not properly connected.

```
   while not link.empty(i) do
      self:process_packet(i, o)
      self.packet_counter = self.packet_counter + 1
   end
end
```

Now we loop over the available packets on `i`and process each individually.
This is a common Snabb idiom. The actual logic of our app is performed by a
call to the `process_packet` method which is defined below. Note that we
increment the `packet_counter` of our instance for every packet processed.

```
function Sprayer:process_packet(i, o)
   local p = link.receive(i)

   -- drop every other packet
   if self.packet_counter % 2 == 0 then
      link.transmit(o, p)
   else
      packet.free(p)
   end
end
```

In the `process_packet` method we first receive a packet `p` from `i`
using `link.receive`. We then decide whether `p` should be transmitted to
`o` using `link.transmit` or dropped, depending on whether
`self.packet_counter` is even or odd. Note that packets which are not
transmitted to another link must be freed using `packet.free`.

We'll use the `example_spray` program defined in
`src/program/example_spray/example_spray.lua` to run our example app. We
will not go over it in detail because it is very similar to the
`example_replay` program explained before. Note though how we require the
newly defined `program.example_spray.sprayer` module and use it when
creating the app network.

```lua
module(..., package.seeall)

local pcap = require("apps.pcap.pcap")
local sprayer = require("program.example_spray.sprayer")

function run (parameters)
   if not (#parameters == 2) then
      print("Usage: example_spray <input> <output>")
      main.exit(1)
   end
   local input = parameters[1]
   local output = parameters[2]

   local c = config.new()
   config.app(c, "capture", pcap.PcapReader, input)
   config.app(c, "spray_app", sprayer.Sprayer)
   config.app(c, "output_file", pcap.PcapWriter, output)

   config.link(c, "capture.output -> spray_app.input")
   config.link(c, "spray_app.output -> output_file.input")

   engine.configure(c)
   engine.main({duration=1, report = {showlinks=true}})
end
```

Here is the expected output if you use the provided `input.pcap` file to
run the `example_spray` program:

```
src/snabb example_spray src/program/example_replay/input.pcap /tmp/out.cap

link report:
                   5 sent on capture.output -> spray_app.input (loss rate: 0%)
                   2 sent on spray_app.output -> output_file.input (loss rate: 0%)
```

The app sent packets numbered 2 and 4. Packets numbered 1, 3, and 5 are discarded.

## Next Steps

Here are some suggested steps to continue learning about Snabb.


1. Read the source documentation. Start with the
[README.md](https://github.com/snabbco/snabb/blob/master/src/README.md)
in the [src](https://github.com/snabbco/snabb/blob/master/src)
directory.
2. Read the code for the example apps in
[basic_apps.lua](https://github.com/snabbco/snabb/blob/master/src/apps/basic/basic_apps.lua).
3. Continue reading the source for other apps in the
[apps](https://github.com/snabbco/snabb/tree/master/src/apps)
directory.
4. Modify the sprayer.lua program to make decisions based on the contents
of the packet's Layer 3 header. Hint: The `snabb` executable must be
rebuilt (using `make`) any time you make changes to apps and/or programs
in order to include your changes.

Don't hesitate to contact the Snabb community on the
[snabb-devel@googlegroups.com](https://groups.google.com/forum/#!forum/snabb-devel)
mailing list.
