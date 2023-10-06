# Data-plane configuration

Wouldn't it be nice if you could update a Snabb program's configuration
while it's running?  Well never fear, `snabb config` is here.  Provided
the data-plane author enabled this feature on their side, users can run
`snabb config` commands to query state or configuration, provide a new
configuration, or incrementally update the existing configuration of a
Snabb instance.

## `snabb config`

`snabb config` is a family of Snabb commands.  Its sub-commands
include:

* [`snabb config get`](./get/README): read configuration data

* [`snabb config get-state`](./get_state/README): read state data

* [`snabb config load`](./load/README): load a new configuration

* [`snabb config set`](./set/README): incrementally update configuration

* [`snabb config add`](./add/README): augment configuration, for
  example by adding a routing table entry

* [`snabb config remove`](./remove/README): remove a component from
  a configuration, for example removing a routing table entry

* [`snabb config listen`](./listen/README): provide an interface to
  the `snabb config` functionality over a persistent socket, to minimize
  per-operation cost

* [`snabb config set-alarm-operator-state`](./set_alarm_operator_state/README):
  add a new operator-state to an alarm

* [`snabb config purge-alarms`](./purge_alarms/README):
  purge alarms by several criteria

* [`snabb config compress-alarms`](./compress_alarms/README): compress entries
  in the alarm list by removing all but the latest state change for all alarms

* [`snabb config shutdown`](./shutdown/README): terminate all workers
  and exit

The `snabb config get` et al commands are the normal way that Snabb
users interact with Snabb applications in an ad-hoc fashion via the
command line.  `snabb config listen` is the standard way that a NETCONF
agent like Sysrepo interacts with a Snabb network function.

### Configuration model

Most `snabb config` commands are invoked in a uniform way:

```
snabb config SUBCOMMAND [-s SCHEMA-NAME] ID PATH [VALUE]
```

`snabb config` speaks a data model that is based on YANG, for minimum
impedance mismatch between NETCONF agents and Snabb applications.  The
`-s SCHEMA-NAME` option allows the caller to indicate the YANG schema
that they want to use, and for the purposes of the lwAFTR might be `-s
ietf-softwire-br`.

`ID` identifies the particular Snabb instance to talk to, and can be a
PID or a name.  Snabb supports the ability for an instance to acquire
a name, which is often more convenient than dealing with changing
PIDs.

`PATH` specifies a subset of the configuration tree to operate on.

Let's imagine that the configuration for the Snabb instance in
question is modelled by the following YANG schema:

```yang
module snabb-simple-router {
  namespace snabb:simple-router;
  prefix simple-router;

  import ietf-inet-types {prefix inet;}

  leaf active { type boolean; default true; }

  leaf-list public-ip { type inet:ipv4-address; }

  container routes {
    list route {
      key addr;
      leaf addr { type inet:ipv4-address; mandatory true; }
      leaf port { type uint8 { range 0..11; }; mandatory true; }
    }
  }
}
```

In this case then, we would pass `-s snabb-simple-router` to all of
our `snabb config` invocations that talk to this router.  Snabb data
planes also declare their "native schema", so if you leave off the
`-s` option, `snabb config` will ask the data plane what schema it uses.

The configuration for a Snabb instance can be expressed in a text
format that is derived from the schema.  In this case it could look
like:

```yang
active true;
routes {
  route { addr 1.2.3.4; port 1; }
  route { addr 2.3.4.5; port 2; }
}
public-ip 10.10.10.10;
public-ip 10.10.10.11;
```

The surface syntax of data is the same as for YANG schemas; you can
have end-of-line comments with `//`, larger comments with `/* ... */`,
and the YANG schema quoting rules for strings apply.

So indeed, `snabb config get ID /` might print out just the output given
above.

By default, `snabb config get` does not print out attributes which
value is the default value.  To print out all attributes, including those
which value is the default, use the knob `--print-default`.  This
knob is also available in `snabb config get-state`.  Example:

```
$ snabb config get --print-default ID /softwire-config/external-interace
allow-incoming-icmp false;
error-rate-limiting {
  packets 600000;
  period 2;
}
generate-icmp-errors true;
ip 10.10.10.10;
mac 12:12:12:12:12:12;
mtu 1460;
next-hop {
  mac 68:68:68:68:68:68;
}
reassembly {
  max-fragments-per-packet 40;
  max-packets 20000;
}
```

In the example above, attributes sucha as `period` and `mtu` take their
default values.  They wouldn't be printed out unless `--print-default`
was used.

In addition, it is possible to print output in two different formats:
Yang or XPath.  By default, output is printed in Yang format.  Here is an
example for XPath formatted output:

```
$ sudo ./snabb config get --format=xpath ID /softwire-config/external-interface
/softwire-config/external-interface/allow-incoming-icmp false;
/softwire-config/external-interface/error-rate-limiting/packets 600000;
/softwire-config/external-interface/ip 10.10.10.10;
/softwire-config/external-interface/mac 12:12:12:12:12:12;
/softwire-config/external-interface/next-hop/mac 68:68:68:68:68:68;
/softwire-config/external-interface/reassembly/max-fragments-per-packet 40;
```

Users can limit their query to a particular subtree via passing a
different `PATH`.  For example, with the same configuration, we can
query just the `active` value:

```
$ snabb config get ID /active
true
```

`PATH` is in a subset of XPath, which should be familiar to NETCONF
operators.  Note that the XPath selector operates over the data, not
the schema, so the path components should reflect the data.

A `list` is how YANG represents associations between keys and values.
To query an element of a `list` item, use an XPath selector; for
example, to get the value associated with the key `1.2.3.4`, do:

```
$ snabb config get ID /routes/route[addr=1.2.3.4]
port 1;
```

Or to just get the port:

```
$ snabb config get ID /routes/route[addr=1.2.3.4]/port
1
```

Likewise, to change the port for `1.2.3.4`, do:

```
$ snabb config set ID /routes/route[addr=1.2.3.4]/port 7
```

If the element has a multiple-value key, you can use multiple XPath
selectors. For instance, if route elements had "addr port" as key,
you'd do:

```
$ snabb config get ID /routes/route[addr=1.2.3.4][port=1]
```

The general rule for paths and value syntax is that if a name appears in
the path, it won't appear in the value.  Mostly this works as you would
expect, but there are a couple of edge cases for instances of `list` and
`leaf-list` nodes.  For example:

```
$ snabb config get ID /routes/route[addr=1.2.3.4]/port
1
$ snabb config get ID /routes/route[addr=1.2.3.4]
port 1;
$ snabb config get ID /routes/route
{
  addr 1.2.3.4;
  port 1;
}
{
  addr 2.3.4.5;
  port 2;
}
$ snabb config get ID /routes
route {
  addr 1.2.3.4;
  port 1;
}
route {
  addr 2.3.4.5;
  port 2;
}
```

Note the case when getting the `list` `/routes/route`:  the syntax is a
sequence of brace-delimited entries.

To select an entry from a `leaf-list`, use the `position()` selector:

```
$ snabb config get ID /public-ip[position()=1]
10.10.10.10
$ snabb config get ID /public-ip[position()=2]
10.10.10.11
```

As you can see, the indexes are 1-based.  The syntax when getting or
setting a `leaf-list` directly by path is similar to the `list` case:  a
sequence of whitespace-delimited bare values.

```
$ snabb config get ID /public-ip
10.10.10.10
10.10.10.11
$ snabb config set ID /public-ip "12.12.12.12 13.13.13.13"
$ snabb config get ID /public-ip
12.12.12.12
13.13.13.13
$ snabb config get ID /
active true;
routes {
  route { addr 1.2.3.4; port 1; }
  route { addr 2.3.4.5; port 2; }
}
public-ip 12.12.12.12;
public-ip 13.13.13.13;
```

Values can be large, so it's also possible to take them from `stdin`.
Do this by omitting the value:

```
$ cat /tmp/my-configuration | snabb config set ID /
```

Resetting the whole configuration is such a common operation that it
has a special command that takes a filesystem path instead of a schema
path:

```
$ snabb config load ID /tmp/my-configuration
```

Using `snabb config load` has the advantage that any configuration
error has a corresponding source location.

`snabb config` can also remove part of a configuration, but only on
configuration that corresponds to YANG schema `list` or `leaf-list`
nodes:

```
$ snabb config remove ID /routes/route[addr=1.2.3.4]
```

One can of course augment a configuration as well:

```
$ snabb config add ID /routes/route
{
  addr 4.5.6.7;
  port 11;
}
```

### Machine interface

The `listen` interface supports all of these operations with a simple
JSON protocol.  `snabb config listen` reads JSON objects from `stdin`,
parses them, relays their action to the data plane, and writes responses
out to `stdout`.  The requests are processed in order, but
asynchronously; `snabb config listen` doesn't wait for a response from
the data plane before processing the next request.  In this way, a
NETCONF agent can pipeline a number of requests.

Each request is a JSON object with the following properties:

- `id`: A request identifier; a string.  Not used by `snabb config
  listen`; just a convenience for the other side.

- `verb`: The action to perform; one of `get-state`, `get`, `set`,
  `add`, or `remove`. A string.

- `path`: A path identifying the configuration or state data on which
  to operate.  A string.

- `value`: Only present for the set and add verbs, a string
  representation of the YANG instance data to set or add. The value is
  encoded as a string in the same syntax that the `snabb config set`
  accepts.

Each response from the server is also one JSON object, with the
following properties:

- `id`: The identifier corresponding to the request.  A string.

- `status`: Either ok or error.  A string.

- `value`: If the request was a `get` request and the status is `ok`,
  then the `value` property is present, containing a `Data`
  representation of the value. A string.

Error messages may have additional properties which can help diagnose
the reason for the error. These properties will be defined in the
future.

```
$ snabb config listen -s snabb-simple-router ID
{ "id": "0", "verb": "get", "path": "/routes/route[addr=1.2.3.4]/port" }
{ "id": "1", "verb": "get", "path": "/routes/route[addr=2.3.4.5]/port" }
{ "id": "0", "status": "ok", "value: "1" }
{ "id": "1", "status": "ok", "value: "2" }
```

The above transcript indicates that requests may be pipelined: the
client to `snabb config` listen may make multiple requests without
waiting for responses. (For clarity, the first two JSON objects in the
above transcript were entered by the user, in the console in this
case; the second two are printed out by `snabb config` in response.)

The `snabb config listen` program acquires exclusive write access to the
data plane, preventing other `snabb config` invocations from modifying
the configuration.  In this way there is no need to provide for
notifications of changes made by other configuration clients.

### Multiple schemas

Support is planned for multiple schemas.  For example the Snabb lwAFTR
uses a native YANG schema to model its configuration and state, but
operators would also like to interact with the lwAFTR using the
relevant standardized schemas.  Work here is ongoing.

## How does it work?

The Snabb instance itself should be running in *multi-process mode*,
whereby there is one manager process that shepherds a number of worker
processes.  The workers perform the actual data-plane functionality, are
typically bound to reserved CPU and NUMA nodes, and have soft-real-time
constraints.  The manager process however doesn't have much to do; it
just coordinates the workers.

The manager process runs a special event loop that listens on a UNIX
socket for remote procedure calls from `snabb config` programs,
translates those calls to updates that the data plane should apply, and
dispatches those updates to the data plane in an efficient way.  See the
[`lib.ptree` documentation](../../lib/ptree/README.md) for full details.

Some data planes, like the lwAFTR, add hooks to the `set`, `add`, and
`remove` subcommands of `snabb config` to allow even more efficient
incremental updates, for example updating the binding table in place via
a custom protocol.
