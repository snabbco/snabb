Usage:
  query [OPTIONS] <pid/name> [<counter-name>]

Options:

  -n, --name        <name>    Name of snabb process.
  -h, --help                  Print usage information.
  -l, --list-all              List all available counter names.

Display current statistics from lwAFTR counters for a running Snabb instance
with <pid>.

If <pid> is empty and there is only one Snabb instance, "query" will
connect to that instance.  It is possible to query a process by name, passing
the flag --name.

If <counter-name> is set, only counters partially matching <counter-name> are
listed.

The values for the counters defined in <src/apps/lwaftr/lwaftr.lua> will be
displayed, but only the ones that are not zero.

It needs root privileges.

Examples:
snabb lwaftr query -l
snabb lwaftr query 1111 in-ipv4
snabb lwaftr query -n mysnabbprocess
