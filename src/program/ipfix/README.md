### ipfix probe

The `ipfix probe` program runs an IPFIX meter and exporter on the
packets coming in on an interface.  It can be invoked like so:

```
./snabb ipfix probe [options] <input> <output>
```

The *input* argument names an interface on which to read traffic, and
*output* indicates the interface on which to send exported UDP
packets.  For example, to take input from the Intel 82599 card at PCI
address `03:00.0`, send output to `03:00.1`, and bind to the CPU 2, do:

```
./snabb ipfix probe --cpu 2 03:00.0 03:00.1
```

Usually you want to run `ipfix probe` using an input interface that
receives a mirror of your "main" traffic flow.

See `./snabb ipfix probe --help` for more documentation on options to
pass to `snabb ipfix probe`, including options to set the IPv4
addresses of the exporter and collector (which default to 10.0.0.1 and
10.0.0.2, respectively).
