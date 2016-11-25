# Config leader and follower

Sometimes you want to query the state or configuration of a running
Snabb data plane, or reload its configuration, or incrementally update
that configuration.  However, you want to minimize the impact of
configuration query and update on data plane performance.  The
`Leader` and `Follower` apps are here to fulfill this need, while
minimizing performance overhead.

The high-level design is that a `Leader` app is responsible for
knowing the state and configuration of a data plane.  The leader
offers an interface to allow the outside world to query the
configuration and state, and to request configuration updates.  To
avoid data-plane overhead, the `Leader` app should be deployed in a
separate process.  Because it knows the data-plane state, it can
respond to queries directly, without involving the data plane.  It
processes update requests into a form that the data plane can handle,
and feeds those requests to the data plane via a high-performance
back-channel.

The data plane runs a `Follower` app that reads and applies update
messages sent to it from the leader.  Checking for update availability
requires just a memory access, not a system call, so the overhead of
including a follower in the data plane is very low.

## Two protocols

The leader communicates with its followers using a private protocol.
Because the leader and the follower are from the same Snabb version,
the details of this protocol are subject to change.  The private
protocol's only design constraint is that it should cause the lowest
overhead for the data plane.

The leader communicates with the world via a public protocol.  The
"snabb config" command-line tool speaks this protocol.  "snabb config
get foo /bar" will find the local Snabb instance named "foo", open the
UNIX socket that the "foo" instance is listening on, issue a request,
then read the response, then close the socket.

## Public protocol

The design constraint on the public protocol is that it be expressive
and future-proof.  We also want to enable the leader to talk to more
than one "snabb config" at a time.  In particular someone should be
able to have a long-lived "snabb config listen" session open, and that
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
  }
  output {
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

## Private protocol

The leader maintains a configuration for the program as a whole.  As
it gets requests, it computes the set of changes to app graphs that
would be needed to apply that configuration.  These changes are then
passed through the private protocol to the follower.  No response from
the follower is necessary.

In some remote or perhaps not so remote future, all Snabb apps will
have associated YANG schemas describing their individual
configurations.  In this happy future, the generic way to ship
configurations from the leader to a follower is by the binary
serialization of YANG data, implemented already in the YANG modules.
Until then however, there is also generic Lua data without a schema.
The private protocol supports both kinds of information transfer.

In the meantime, the way to indicate that an app's configuration data
conforms to a YANG schema is to set the `schema_name` property on the
app's class.

The private protocol consists of binary messages passed over a ring
buffer.  A follower's leader writes to the buffer, and the follower
reads from it.  There are no other readers or writers.  Given that a
message may in general be unbounded in size, whereas a ring buffer is
naturally fixed, messages which may include arbtrary-sized data may be
forced to put that data in the filesystem, and refer to it from the
messages in the ring buffer.  Since this file system is backed by
`tmpfs`, stalls will be minimal.

## User interface

The above sections document how the leader and follower apps are
implemented so that a data-plane developer can understand the overhead
of run-time (re)configuration.  End users won't be typing at a UNIX
socket though; we include the `snabb config` program as a command-line
interface to this functionality.

See [the `snabb config` documentation](../../program/config/README.md)
for full details.
