Usage: ptree --help
       ptree [OPTION...] SCHEMA.YANG SETUP.LUA CONF

Run a multi-process network function.  The dataplane is constructed by
the the "setup function" defined in SETUP.LUA.  This function takes
configuration data conforming to a specified YANG schema as an argument,
and returns table mapping worker ID to the corresponding graph of apps
and links (a "core.config" object).

This "ptree" program is so named because it uses the "lib.ptree" process
tree facility from Snabb.  It's useful for prototyping network functions
and can be a good starting point for a new network function -- just copy
its code and modify to suit.

The management process in a "ptree" network function listens on a socket
for configuration queries and updates.  Users can change the network
function's configuration while it is running using the "snabb config"
program.  The management process will use the setup function to compute
new app graphs for the workers and then apply any needed changes to the
workers.

Optional arguments:
       -n NAME, --name NAME     Sets the name as the identifier of this program.
                                This must be unique amongst other snab programs.
       --cpu <cpuset>           Run data-plane processes on the given CPUs.
       --real-time              Enable real-time SCHED_FIFO scheduler on
                                data-plane processes.
       --on-ingress-drop=ACTION Specify an action to take in a data-plane if
                                too many ingress drops are detected.  Available
                                actions: "warn" to print a warning, "flush"
                                to flush the JIT, or "off" to do nothing.
                                Default is "flush".
       -D       <seconds>       Duration in seconds.
       -v                       Verbose (repeat for more verbosity).
       -t FILE, --trace FILE    File to which to write a trace of incoming RPCs.

CPUSET is a list of CPU ranges.  For example "3-5,7-9", or "3,4,5,7,8,9"
both allow the data planes to run on the given CPUs.
