Data Format Usage:
  snabb config get-state <instance identifier> <path>

This command takes in a instance identifier (a name or a PID) and a path to
inside the schema and will display the statistics at that path. The program
will find the conters specified under the path and match those to counters
defined in the apps.

Example usage:

  $ snabb config get-state lwaftr1 /softwire-state/
