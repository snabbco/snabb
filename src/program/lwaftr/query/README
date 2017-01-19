Usage:
  query [OPTIONS] [<id>] [<counter-name>]

Options:

  -h, --help                    Print usage information.
  -l, --list-all                List all available counter names.

Display current statistics from lwAFTR counters for a running Snabb instance
with <id>.  <id> can be either a PID or a string ID:

   * If it is a PID, <id> should exists at /var/run/snabb/<id>.
   * If it is a string ID, <id> should match the value defined
     in /var/run/snabb/*/nic/id.

If <pid> is not supplied and there is only one Snabb instance, "query" will
connect to that instance.

If <counter-name> is set, only counters partially matching <counter-name> are
listed.

The values for the counters defined in <src/apps/lwaftr/lwaftr.lua> will be
displayed, but only the ones that are not zero.

It needs root privileges.
