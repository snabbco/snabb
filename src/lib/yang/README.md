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
    presence true;
    list route {
      key addr;
      leaf addr { type inet:ipv4-address; mandatory true; }
      leaf port { type uint8 { range 0..11; }; mandatory true; }
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

- A `container`'s configuration can be one of two ways.  Firstly, if
  its `presence` attribute is `true`, then the container's
  configuration is the container's keyword followed by the
  configuration of its data node children, like `keyword {
  configuration... }`.  Otherwise if its `presence` is `false`, then a
  container's configuration is just its data node children's
  configuration, in any order.

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
port 1; addr 1.2.3.4; }`.  Note that if `presence` is false (the
default), the grammar is the same except there's no outer `routes { }`
wrapper; the `route` statements would be at the same level as
`active`.

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

#### Querying and updating configurations

#### State data

#### Function reference

All of these functions are on modules in the `lib.yang` path.  For
example, to have access to:

— Function **schema.load_schema_by_name** *name*

Then do `local schema = require('lib.yang.schema')`.

— Function **schema.load_schema_by_name** *name*

Load up schema by name.  [TODO write more here.]
