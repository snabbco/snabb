Usage:
    monitor IPV4_ADDRESS PID

Options:

    -n, --name    <name>    Name of snabb process.
    -h, --help              Print usage information.

Arguments:

    IPV4_ADDRESS            IPv4 address to mirror.
    PID                     PID value of Snabb process.

Sets the value of 'v4v6_mirror' counter to IPV4_ADDRESS.  The 'v4v6_mirror'
counter is defined for all lwAFTR instances running in mirroring mode.
Matching packets will be mirrored to the tap interface set by the original
lwAFTR process.

It is possible to query a process by name, passing the flag --name.

IPV4_ADDRESS can take two special values:

- 'none', which is equivalent to '0.0.0.0'.
- 'all', which is equivalent to '255.255.255.255'.

PID value is used to retrieve the lwAFTR instance.
