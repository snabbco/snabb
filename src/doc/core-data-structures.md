## Core data structures

Software architectures can sometimes be summarized with a few key data
structures.

Unix is about processes, pipes, and files. Processes are executing
code, pipes are FIFO byte buffers, and files are binary storage.

Emacs is about text, buffers, and windows. Text is strings of
characters with key-value properties, buffers are collections of text
and positional markers, and windows are user-visible screen areas that
display parts of buffers.

Snabb Switch is about **packets**, **links**, and **apps**.

### Packets

Packets are the basic inputs and outputs of Snabb Switch. A packet is
simply a variable-size array of binary data. Packets usually contain
data in an Ethernet-based format but this is only a convention.

```
struct packet {
  unsigned char payload[10240];
  uint16_t length;
}
```

Packets on the wire in physical networks are bits encoded as a series
of electrical or optical impulses. Snabb Switch just encodes those
same bits into memory.

### Links

A link collects a series of packets for processing by an app. Links between apps serve a similar purpose to ethernet cables between network devices, except that links are unidirectional. Links are represented as simple [ring buffers](https://en.wikipedia.org/wiki/Circular_buffer) of packets.

```
struct link {
  struct packet *packets[256];
  int read, write; // ring cursor positions
}
```

### Apps

Apps are the active part of Snabb Switch. Each app performs either or both of these functions:

1. "Pull" new packets into Snabb Switch by receiving data from the outside world (e.g. a network interface card) and placing them onto output links for processing.
2. "Push" existing packets from input links through the next step of their processing: output onto a real network, transfer onto one or more output links for processing by other apps, perform filtering or transformation, and so on.

In principle an app is a piece of machine code: anything that can execute. In practice an app is represented as a Lua object and executes code compiled by LuaJIT. (This code can easily call out to C, assembler, or other languages but in practice it seldom does.)

```
{
  input  = { ... },     -- Table of named input links
  output = { ... },     -- Table of named output links
  pull   = <function>,  -- Function to "pull" new packets into the system.
  push   = <function>   -- Function to "push" existing packets onward.
}
```

### Summary

Those are the most important data structures in Snabb Switch. To do
serious Snabb Switch development you only need to write some code that
manipulates packets and links. Usually we write apps in Lua using some
common libraries, but you can realistically write them from scratch in
Lua, C, assembler, or anything else you care to link in.

