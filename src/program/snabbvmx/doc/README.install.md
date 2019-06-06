# Installation

## How to install it

Snabb is a programming network toolkit as well as a ready-to-use network
utilities suite.  The Snabb executable features several Snabb programs:

```bash
$ sudo ./snabb
Usage: ./snabb <program> ...

This snabb executable has the following programs built in:
  example_replay
  example_spray
  firehose
  lisper
  lwaftr
  packetblaster
  pci_bind
  snabbmark
  snabbnfv
  snabbvmx
  snsh
  test
  top
```

Type `snabb <program>` to run a specific program.  Usually a simple program
call prints out its user help:

```bash
$ sudo ./snabb snabbvmx
Usage:
    snabbvmx check
    snabbvmx lwaftr
    snabbvmx query

Use --help for per-command usage.

Example:
    snabbvmx lwaftr --help
```

There is no specific script to install a snabb executable.  Once it's built,
a snabb executable includes all its dependencies, including a LuaJIT interpreter,
in a single binary.  Thus, it's possible to relocate a snabb executable to any
folder in the system.  Move it to a folder in PATH, so the system can always
locate it:

```bash
$ echo $PATH
/home/user/bin:/opt/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:
/usr/bin:/sbin:/bin

$ cp snabb /opt/local/bin
```

When the snabb executable is renamed to one of its featured programs, it will
run the program it's named after.  For instance, to always run snabbvmx simply
rename snabb to snabbvmx.

```bash
$ mv snabb snabbvmx
$ sudo ./snabbvmx
Usage:
    snabbvmx check
    snabbvmx lwaftr
    snabbvmx query
```

## SnabbVMX tools

The SnabbVMX program (**program/snabbvmx/**) features a series of subcommands
or tools:

- **check**: Verifies the correctness of the lwAFTR logic.
- **nexthop**: Retrieves the nexthop cached values (available in shared memory).
- **query**: Checks out the counter values of a running SnabbVMX instance.
- **lwaftr**: Main program. Sets up the SnabbVMX network design and runs it.
- **top**: Similar to Snabb's top. Prints out Gb and Mpps in IPv4 and IPv6
  interfaces.  Includes reports about counters and ingress-packet-drops.

There is an additional program in snabb called **packetblaster**.  Packetblaster
includes a *lwaftr* mode. This mode is very useful to generate live traffic matching
a binding-table.

```bash
 $ ./snabb packetblaster lwaftr --src_mac 02:02:02:02:02:02 \
                                --dst_mac 02:42:df:27:05:00 \
                                --b4 2001:db8::40,10.10.0.0,1024 \
                                --aftr 2001:db8:ffff::100 \
                                --count 60001 --rate 3.1 --pci 0000:05:00.1
```

Please check the [How to use it?](README.userguide.md) chapter for a more
detailed view of each tool.
