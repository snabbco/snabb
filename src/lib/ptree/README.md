# Process tree (`lib.ptree`)

When prototyping a network function, it's useful to start with a single
process that does packet forwarding.  A first draft of a prototype
network function will take its configuration from command line
arguments; once it's started, you can read some information from it via
its counters but you can't affect its operation to make it do something
else without restarting it.

As you grow a prototype network function into a production system, new
needs arise.  You might want to query the state or configuration of a
running Snabb data plane.  You might want to reload its configuration,
or incrementally update that configuration.  However, as you add these
new capabilities, you want to minimize their impact on data plane
performance.  The process tree facility is here to help with these tasks
by allowing a network function to be divided into separate management
and data-plane processes.

Additionally, as a network function grows, you might want to dedicate
multiple CPU cores to dataplane tasks.  Here too `lib.ptree` helps out,
as a management process can be responsible for multiple workers.  All
you need to do is to write a function that maps your network function's
configuration to a set of app graphs\* (as a table from worker ID to app
graph).  Each app graph in the result will be instantiated on a separate
worker process.  If the configuration changes at run-time resulting in a
different set of worker IDs, the `ptree` manager will start new
workers and stop any old workers that are no longer necessary.

\*: An "app graph" is an instance of `core.config`.  The `ptree`
facility reserves the word "configuration" to refer to the user-facing
configuration of a network function as a whole, and uses "app graph" to
refer to the network of Snabb apps that runs in a single worker
data-plane process.

The high-level design is that a manager from `lib.ptree.ptree` is
responsible for knowing the state and configuration of a data plane.
The manager also offers an interface to allow the outside world to query
the configuration and state, and to request configuration updates.
Because it knows the data-plane state, the manager can respond to
queries directly, without involving the data plane.  It processes update
requests into a form that the data plane(s) can handle, and feeds those
requests to the data plane(s) via a high-performance back-channel.

The data planes are started and stopped by the manager as needed.
Internally they run a special main loop from `lib.ptree.worker` which,
as part of its engine breathe loop, also reads and applies update
messages sent to it from the manager.  Checking for update availability
requires just a memory access, not a system call, so the overhead of the
message channel on the data plane is very low.

The ptree manager will also periodically read counter values from the
data-plane processes that it manages, and aggregates them into
corresponding counters associated with the manager process.  For
example, if two workers have an `apps/if/drops.counter` file, then the
manager will also expose an `apps/if/drops.counter`, whose value is the
sum of the counters from the individual workers, plus an archived
counter value that's the sum of counters from workers before they shut
down.

Finally, all of these periodically sampled counters from the workers as
well as the aggregate counters from the manager are also written into
[RRD files](../README.rrd.md), as a kind of "flight recorder" black-box
record of past counter change rates.  This facility, limited by default
to the last 7 days, complements a more long-term statistics database,
and is mostly useful as a debugging and troubleshooting resource.  To
view this historical data, use [`snabb top`](../../program/top/README).

## Example

See [the example `snabb ptree` program](../../program/ptree/README.md)
for a full example.

## API reference

The public interface to `ptree` is the `lib.ptree.ptree` module.

— Function **ptree.new_manager** *parameters*

Create and start a new manager for a `ptree` process tree.  *parameters*
is a table of key/value pairs.  The following keys are required:

 * `schema_name`: The name of a YANG schema describing this network function.
 * `setup_fn`: A function mapping a configuration to a worker set.  A
   worker set is a table mapping worker IDs to app graphs (`core.config`
   instances).  See [the setup function described in the `snabb ptree`
   documentation](../../program/ptree/README.md) for a full example.
 * `initial_configuration`: The initial network configuration for the
   network function, for example as returned by
   `lib.yang.yang.load_configuration`.  Must be an instance of
   `schema_name`.

Optional entries that may be present in the *parameters* table include:

 * `rpc_socket_file_name`: The name of the socket on which to listen for
   incoming connections from `snabb config` clients.  See [the `snabb
   config` documentation](../../program/config/README.md) for more
   information.  Default is `$SNABB_SHM_ROOT/PID/config-leader-socket`,
   where the `$SNABB_SHM_ROOT` environment variable defaults to
   `/var/run/snabb`.
 * `notification_socket_file_name`: The name of the socket on which to
   listen for incoming connections from `snabb alarms` clients.  See
   [the `snabb alarms` documentation](../../program/alarms/README.md)
   for more information.  Default is
   `$SNABB_SHM_ROOT/PID/notifications`.
 * `name`: A name to claim for this process tree.  `snabb config` can
   address network functions by name in addition to PID.  If the name is
   already claimed on the local machine, an error will be signalled.
   The name will be released when the manager stops.  Default is not to
   claim a name.
 * `worker_default_scheduling`: A table of scheduling parameters to
   apply to worker processes, suitable for passing to
   `lib.scheduling.apply()`.
 * `default_schema`: Some network functions can respond to `snabb
   config` queries against multiple schemas.  This parameter indicates
   the default schema to expose, and defaults to *schema_name*.  Using
   an alternate default schema requires a bit of behind-the-scenes
   plumbing to work though from `lib.ptree.support`; see the code for
   details.
 * `log_level`: One of `"DEBUG"`, `"INFO"`, or `"WARN"`.  Default is
   `"WARN"`.
 * `cpuset`: A set of CPUs to devote to data-plane processes; an
   instance of `lib.cpuset.new()`.  Default is
   `lib.cpuset.global_cpuset()`.  The manager will try to bind
   data-plane worker processes to CPUs local to the NUMA node of any PCI
   address being used by the worker.
 * `Hz`: Frequency at which to poll the config socket.  Default is
   1000.
 * `rpc_trace_file`: File to which to write a trace of incoming RPCs
   from "snabb config".  The trace is written in a format that can later
   be piped to "snabb config listen" to replay the trace.

The return value is a ptree manager object, whose public methods are as
follows:

— Manager method **:run** *duration*

Run a process tree, servicing configuration and state queries and
updates from remote `snabb config` clients, managing a tree of workers,
feeding configuration updates to workers, and receiving state and alarm
updates from those workers.  If *duration* is passed, stop after that
many seconds; otherwise continue indefinitely.

— Manager method **:stop**

Stop a process tree by sending a shutdown message to all workers,
waiting for them to shut down for short time, then forcibly terminating
any remaining worker processes.  The manager's socket will be closed and
the Snabb network function name will be released.

## Internals

### Two protocols

The manager communicates with its worker using a private protocol.
Because the manager and the worker are from the same Snabb version, the
details of this protocol are subject to change.  The private protocol's
only design constraint is that it should cause the lowest overhead for
the data plane.

The manager communicates with the world via a public protocol.  The
"snabb config" command-line tool speaks this protocol.  "snabb config
get foo /bar" will find the local Snabb instance named "foo", open the
UNIX socket that the "foo" instance is listening on, issue a request,
then read the response, then close the socket.

### Public protocol

The design constraint on the public protocol is that it be expressive
and future-proof.  We also want to enable the manager to talk to more
than one "snabb config" at a time.  In particular someone should be able
to have a long-lived "snabb config listen" session open, and that
shouldn't impede someone else from doing a "snabb config get" to read
state.

To this end the public protocol container is very simple:

```
Message = Length "\n" RPC*
```

Length is a base-10 string of characters indicating the length of the
message.  There may be a maximum length restriction.  This requires
that "snabb config" build up the whole message as a string and measure
its length, but that's OK.  Knowing the length ahead of time allows
"snabb config" to use nonblocking operations to slurp up the whole
message as a string.  A partial read can be resumed later.  The
message can then be parsed without fear of blocking the main process.

The RPC is an RPC request or response for the
[`snabb-config-leader-v1` YANG
schema](../../lib/yang/snabb-config-leader-v1.yang), expressed in the
Snabb [textual data format for YANG data](../../lib/yang/README.md).
For example the `snabb-config-leader-v1` schema supports a
`get-config` RPC defined like this in the schema:

```yang
rpc get-config {
  input {
    leaf schema { type string; mandatory true; }
    leaf revision { type string; }
    leaf path { type string; default "/"; }
    leaf print-default { type boolean; }
    leaf format { type string; }
  }
  output {
    leaf status { type uint8; default 0; }
    leaf error { type string; }
    leaf config { type string; }
  }
}
```

A request to this RPC might look like:

```yang
get-config {
  schema snabb-softwire-v1;
  path "/foo";
}
```

As you can see, non-mandatory inputs can be left out.  A response
might look like:

```yang
get-config {
  config "blah blah blah";
}
```

Responses are prefixed by the RPC name.  One message can include a
number of RPCs; the RPCs will be made in order.  See the
[`snabb-config-leader-v1` YANG
schema](../../lib/yang/snabb-config-leader-v1.yang) for full details
of available RPCs.

### Private protocol

The manager maintains a configuration for the network function as a
whole.  As it gets requests, it computes the set of changes to worker
app graphs that would be needed to apply that configuration.  These
changes are then passed through the private protocol to the specific
workers.  No response from the workers is necessary.

In some remote or perhaps not so remote future, all Snabb apps will have
associated YANG schemas describing how they may be configured.  In this
happy future, the generic way to ship app configurations from the
manager to a worker is by the binary serialization of YANG data,
implemented already in the YANG modules.  Until then however, there is
also generic Lua data without a schema.  The private protocol supports
both kinds of information transfer.

In the meantime, the way to indicate that an app's configuration data
conforms to a YANG schema is to set the `schema_name` property on the
app's class.

The private protocol consists of binary messages passed over a ring
buffer.  A worker's manager writes to the buffer, and the worker reads
from it.  There are no other readers or writers.  Given that a message
may in general be unbounded in size, whereas a ring buffer is naturally
fixed, messages which may include arbitrary-sized data may be forced to
put that data in the filesystem, and refer to it from the messages in
the ring buffer.  Since this file system is backed by `tmpfs`, stalls
will be minimal.

## User interface

The above sections document how the manager and worker libraries are
implemented so that a data-plane developer can understand the overhead
of using `lib.ptree` in their network function.  End users won't be
typing at a UNIX socket though; we include the `snabb config` program as
a command-line interface to this functionality.

See [the `snabb config` documentation](../../program/config/README.md)
for full details.
