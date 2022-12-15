### Snabb program configuration with YANG (`lib.yang`)

YANG is a data modelling language designed for use in networking
equipment, standardized as [RFC
6020](https://tools.ietf.org/html/rfc6020).  The `lib.yang` modules
provide YANG facilities to Snabb applications, allowing operators to
understand how to work with a Snabb data plane and also providing
convenient configuration facilities for data-plane authors.

#### Overview

Everything in YANG starts with a *schema*: a specification of the data
model of a device.  For example, consider a simple Snabb router that
receives IPv4 traffic and sends it out one of 12 ports.  We might
model it like this:

```yang
module snabb-simple-router {
  namespace snabb:simple-router;
  prefix simple-router;

  import ietf-inet-types {prefix inet;}

  leaf active { type boolean; default true; }

  container routes {
    list route {
      key addr;
      leaf addr { type inet:ipv4-address; mandatory true; }
      leaf port { type uint8 { range 0..11; } mandatory true; }
    }
  }
}
```

Given this schema, `lib.yang` can automatically derive a configuration
file format for this Snabb program and create a parser that applies
the validation constraints from the schema.  The result is a simple
plain-old-data Lua object that the data-plane can use directly.

Additionally there is support for efficient binary compilation of
configurations.  The problem is that even in this simple router, the
routing table can grow quite large.  While particular applications can
sometimes incrementally update their configurations without completely
reloading the configuration from the start, in general reloading is
almost always a possibility, and you want to avoid packet loss during
the time that the millions of routing table entries are loaded and
validated.

For that reason the `lib.yang` code also defines a mapping that, given
a YANG schema, can compile any configuration for that schema into a
pre-validated binary file that the data-plane can just load up
directly.  Additionally for `list` nodes that map between keys and
values, the `lib.yang` facilities can compile that map into an
efficient [`ctable`](../README.ctable.md), letting the data-plane use
the configuration as-is.

The schema given above can be loaded from a string using `load_schema`
from the `lib.yang.schema` module, from a file via `load_schema_file`,
or by name using `load_schema_by_name`.  This last interface allows
one to compile a YANG schema into the Snabb binary directly; if we
name the above file `snabb-simple-router.yang` and place it in the
`src/lib/yang` directory, then
`load_schema_by_name('snabb-simple-router')` will find it
appropriately.  Indeed, this is how the `ietf-inet-types` import in
the above example was resolved.

#### Configuration syntax

Consider again the example `snabb-simple-router` schema.  To configure
a router, we need to provide a configuration in a way that the
application can understand.  In Snabb, we derive this configuration
syntax from the schema, in the following way:

- A `module`'s configuration is composed of the configurations of all
  data nodes (`container`, `leaf-list`, `list`, and `leaf`) nodes
  inside it.

- A `leaf`'s configuration is like `keyword value;`, where the keyword
  is the name of the leaf, and the value is in the right syntax for
  the leaf's type.  (More on value types below.)

- A `container`'s configuration is the container's keyword followed by
  the configuration of its data node children, like `keyword {
  configuration... }`.

- A `leaf-list`'s configuration is a sequence of 0 or more instances
  of `keyword value;`, as in `leaf`.

- A `list`'s configuration is a sequence of 0 or more instances of the
  form `keyword { configuration... }`, again where `keyword` is the
  list name and `configuration...` indicates the configuration of
  child data nodes.

Concretely, for the example configuration above, the above algorithm
derives a configuration format of the following form:

```
(active true|false;)?
(routes {
  (route { addr ipv4-address; port uint8; })*
})?
```

In this grammar syntax, `(foo)?` indicates either 0 or 1 instances of
`foo`, `(foo)*` is similar bit indicating 0 or more instances, and `|`
expresses alternation.

An example configuration might be:

```
active true;
routes {
  route { addr 1.2.3.4; port 1; }
  route { addr 2.3.4.5; port 10; }
  route { addr 3.4.5.6; port 2; }
}
```

Except in special cases as described in RFC 6020, order is
insignificant.  You could have `active false;` at the end, for
example, and `route { addr 1.2.3.4; port 1; }` is the same as `route {
port 1; addr 1.2.3.4; }`.

The surface syntax of our configuration format is the same as for YANG
schemas; `"1.2.3.4"` is the same as `1.2.3.4`.  Snabb follows the XML
mapping guidelines of how to represent data described by a YANG
schema, except that it uses YANG syntax instead of XML syntax.  We
could generate XML instead, but we want to avoid bringing in the
complexities of XML parsing to Snabb.  We also think that the result
is a syntax that is pleasant and approachable to write by hand; we
want to make sure that everyone can use the same configuration format,
regardless of whether they are configuring Snabb via an external
daemon like `sysrepo` or whether they write configuration files by
hand.

#### Compiled configurations

Loading a schema and using it to parse a data file can be a bit
expensive, especially if the data file includes a large routing table or
other big structure.  It can be useful to pay for this this parsing and
validation cost "offline", without interrupting a running data plane.

For this reason, Snabb support compiling configurations to binary
data.  A data plane can load a compiled configuration without any
validation, very cheaply.  Users can explicitly call the
`compile_config_for_schema` or `compile_config_for_schema_by_name`
functions.  Support is planned also for automatic compilation and of
source configuration files as well, so that the user can just edit
configurations as text and still take advantage of the speedy binary
configuration loads when nothing has changed.

#### Querying and updating configurations

[TODO] We will need to be able to serialize a configuration back to
source, for when a user asks what the configuration of a device is.  We
will also need to serialize partial configurations, for when the user
asks for just a part of the configuration.

[TODO] We will need to support updating the configuration of a running
snabb application.  We plan to compile the candidate configuration in a
non-worker process, then signal the worker to reload its configuration.

[TODO] We will need to support incremental configuration updates, for
example to add or remove a binding table entry for the lwAFTR.  In this
way we can avoid a full reload of the configuration, minimizing packet
loss.

#### State data

[TODO] We need to map the state data exported by a Snabb process
(counters, etc) to YANG-format data.  Perhaps this can be done in a
similar way as configuration compilation: the configuration facility in
the Snabb binary compiles a YANG state data file and periodically
updates it by sampling the data plane, and then we re-use the
configuration serialization facilities to serialize (potentially
partial) state data.

#### API reference

The public entry point to the YANG library is the `lib.yang.yang`
module, which exports the following bindings.  Note that unless you have
special needs, probably the only one you want to use is
`load_configuration`.

— Function **load_configuration** *filename* *parameters*

Load a configuration from disk.  If *filename* is a compiled
configuration, load it directly.  Otherwise it must be a source file.
In that case, try to load a corresponding compiled file instead if
possible.  If all that fails, actually parse the source configuration,
and try to residualize a corresponding compiled file so that we won't
have to go through the whole thing next time.

*parameters* is a table of key/value pairs.  The following key is
required:

 * `schema_name`: The name of the YANG schema that describes the
   configuration.   This is the name that appears as the *id* in `module
   id { ... }` in the schema.

Optional entries that may be present in the *parameters* table include:

 * `verbose`: Set to true to print verbose information about which files
   are being loaded and compiled.
 * `revision_date`: If set, assert that the loaded configuration was
   built against this particular schema revision date.

For more information on the format of the returned value, see the
documentation below for `load_config_for_schema`.

— Function **load_schema** *src* *filename*

Load a YANG schema from the string *src*.  *filename* is an optional
file name for use in error messages.  Returns a YANG schema object.

Schema objects do have useful internal structure but they are not part
of the documented interface.

— Function **load_schema_file** *filename*

Load a YANG schema from the file named *filename*.  Returns a YANG
schema object.

— Function **load_schema_by_name** *name* *revision*

Load the given named YANG schema.  The *name* indicates the canonical
name of the schema, which appears as `module *name* { ... }` in the YANG
schema itself, or as `import *name* { ... }` in other YANG modules that
import this module.  *revision* optionally indicates that a certain
revision data should be required.

— Function **add_schema** *src* *filename*

Add the YANG schema from the string *src* to Snabb's database of YANG
schemas, making it available to `load_schema_by_name` and related
functionality.  *filename* is used when signalling any parse errors.
Returns the name of the newly added schema.

— Function **add_schema_file** *filename*

Like `add_schema`, but reads the YANG schema in from a file.  Returns
the name of the newly added schema.

— Function **load_config_for_schema** *schema* *src* *filename*

Given the schema object *schema*, load the configuration from the string
*src*.  Returns a parsed configuration as a plain old Lua value that
tries to represent configuration values using appropriate Lua types.

The top-level result from parsing will be a table whose keys are the
top-level configuration options.  For example in the above example:

```
active true;
routes {
  route { addr 1.2.3.4; port 1; }
  route { addr 2.3.4.5; port 10; }
  route { addr 3.4.5.6; port 2; }
}
```

In this case, the result would be a table with two keys, `active` and
`routes`.  The value of the `active` key would be Lua boolean `true`.

The `routes` container is just another table of the same kind.

Inside the `routes` container is the `route` list, which is represented
as an associative array.  The particular representation for the
associative array depends on characteristics of the `list` type; see
below for details.  In this case the `route` list compiles to a
[`ctable`](../README.ctable.md).  Therefore to get the port for address
1.2.3.4, you would do:

```lua
local yang = require('lib.yang.yang')
local ipv4 = require('lib.protocol.ipv4')
local data = yang.load_config_for_schema(router_schema, conf_str)
local port = data.routes.route:lookup_ptr(ipv4:pton('1.2.3.4')).value.port
assert(port == 1)
```

Here we see that integer values like the `port` leaves are represented
directly as Lua numbers, if they fit within the `uint32` or `int32`
range.  Integers outside that range are represented as `uint64_t` if
they are positive, or `int64_t` otherwise.

Boolean values are represented using normal Lua booleans, of course.

String values are just parsed to Lua strings, with the normal Lua
limitation that UTF-8 data is not decoded.  Lua strings look like
strings but really they are byte arrays.

There is special support for the `ipv4-address`, `ipv4-prefix`,
`ipv6-address`, and `ipv6-prefix` types from `ietf-inet-types`, and
`mac-address` from `ietf-yang-types`.  Values of these types are instead
parsed to raw binary data that is compatible with the relevant parts of
Snabb's `lib.protocol` facility.

Let us return to the representation of compound configurations, like
`list` instances.  A compound configuration whose shape is *fixed* is
compiled to raw FFI data.  A configuration's shape is determined by its
schema.  A schema node whose data will be fixed is either a leaf whose
type is numeric or boolean and which is either mandatory or has a
default value, or a container (`leaf-list`, `container`, or `list`)
whose elements are all themselves fixed.

In practice this means that a fixed `container` will be compiled to an
FFI `struct` type.  This is mostly transparent from the user
perspective, as in LuaJIT you access struct members by name in the same
way as for normal Lua tables.

A fixed `leaf-list` will be compiled to an FFI array of its element
type, but on the Lua side is given the normal 1-based indexing and
support for the `#len` length operator via a wrapper.  A non-fixed
`leaf-list` is just a Lua array (a table with indexes starting from 1).

Instances of `list` nodes are compiled to `lib.yang.list` objects. These behave mostly like regular Lua tables but are really hash tries underneath and support multi-key lookup and are ordered. A list with a single key *foo* behaves just like a Lua table:

```lua
list[x] -- entry with foo==x
list[x] = y -- add or update entry with foo==x
```

A List with two keys *foo* and *bar* can be used like so:

```lua
list[{foo=x, bar=y}] -- entry with key {foo=x, bar=y}
list[{foo=x, bar=y}] = z -- add or update entry
```

In both cases the lists can be iterated in order with `ipairs` and `pairs`.
For single-key lists `pairs` works as expected.
For multi-key lists `pairs` is identical to `ipairs` (keys are included in the entry table.)

Note that there are a number of value types that are not implemented,
including some important ones like `union`.

— Function **load_config_for_schema_by_name** *schema_name* *name* *filename*

Like `load_config_for_schema`, but identifying the schema by name instead
of by value, as in `load_schema_by_name`.

— Function **print_config_for_schema** *schema* *data* *file*

Serialize the configuration *data* as text via repeated calls to the
`write` method of *file*.  At the end, the `flush` method is called on
*file*.  *schema* is the schema that describes *data*.

— Function **compile_config_for_schema** *schema* *data* *filename* *mtime*

Compile *data*, using a compiler generated for *schema*, and write out
the result to the file named *filename*.  *mtime*, if given, should be a
table with `secs` and `nsecs` keys indicating the modification time of
the source file.  This information will be serialized in the compiled
file, and may be used when loading the file to determine whether the
configuration is up to date.

— Function **compile_config_for_schema_by_name** *schema_name* *data* *filename* *mtime*

Like `compile_config_for_schema_by_name`, but identifying the schema
by name instead of by value, as in `load_schema_by_name`.

— Function **load_compiled_data_file** *filename*

Load the compiled data file at *filename*.  If the file is not a
compiled YANG configuration, an error will be signalled.  The return
value will be table containing four keys:

 * `schema_name`: The name of the schema for which this file was
    compiled.
 * `revision_date`: The revision date  of the schema for which this file
    was compiled, or the empty string (`''`) if unknown.
 * `source_mtime`: An `mtime` table, as for `compile_config_for_schema`.
    If no mtime was written into the file, both `secs` and `nsecs` will
    be zero.
 * `data`: The configuration data, in the same format as returned by
    `load_config_for_schema`.
