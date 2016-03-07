# Binding tables

A binding table is a collection of softwires (tunnels).  One endpoint
of the softwire is in the AFTR and the other is in the B4.  A
softwire provisions an IPv4 address (or a part of an IPv4 address) to
a customer behind a B4.  The B4 arranges for all IPv4 traffic to be
encapsulated in IPv6 and sent to the AFTR; the AFTR does the reverse.
The binding table is how the AFTR knows which B4 is associated with
an incoming packet.

## File structure

There are three parts of a binding table: the PSID info map, the
border router (BR) address table, and the softwire map.  Grammatically
they appear in the file in the following order,:

```
  psid_map {
    ...
  }
  br_addresses {
    ...
  }
  softwires {
    ...
  }
```

## PSID info map

The PSID info map defines the set of IPv4 addresses that are provisioned
by an lwAFTR.  It also defines the way in which those addresses are
shared, by specifying the "psid_length" and "shift" parameters for each
address.  See RFC 7597 for more details on the PSID scheme for how to
share IPv4 addresses.  The `psid_map` clause is composed of a list of
entries, each of which specifying a set of IPv4 address and the PSID
parameters.  In this and other clauses, newlines and other white space
are insignificant.  For example:

``
  psid_map {
    1.2.3.4 { psid_length=10 }
    5.6.7.8 { psid_length=5, shift=11 }
    ...
  }
``

An entry's `psid_length` and `shift` parameters must necessarily add up
to 16, so it is sufficient to specify just one of them.  If neither are
specified, they default to 0 and 16, respectively.

The addresses may be specified as ranges or lists of ranges as well:

```
  psid_map {
    1.2.3.4 { psid_length=10 }
    2.0.0.0, 3.0.0.0, 4.0.0.0-4.1.2.3 { psid_length=7 }
  }
```

The set of IPv4 address ranges specified in the PSID info map must be
disjoint.

## Border router addresses

Next, the `br_addresses` clause lists the set of IPv6 addresses to
associate with the lwAFTR.  These are the "border router" addresses.
For a usual deployment there will be one main address and possibly some
additional ones.  For example:

```
  br_addresses {
    8:9:a:b:c:d:e:f,
    1E:1:1:1:1:1:1:af,
    1E:2:2:2:2:2:2:af
  }
```

## Softwires

Finally, the `softwires` clause defines the set of softwires to
provision.  Each softwire associates an IPv4 address, a PSID, and a B4
address.  For example:

```
  softwires {
    { ipv4=178.79.150.233, psid=80, b4=127:2:3:4:5:6:7:128 }
    { ipv4=178.79.150.233, psid=2300, b4=127:11:12:13:14:15:16:128 }
    ...
  }
```

By default, a softwire is associated with the first entry in
`br_addresses` (`aftr=0`).  To associate the tunnel with a different
border router, specify it by index:

```
  softwires {
    { ipv4=178.79.150.233, psid=80, b4=127:2:3:4:5:6:7:128, aftr=0 }
    { ipv4=178.79.150.233, psid=2300, b4=127:11:12:13:14:15:16:128, aftr=42 }
    ...
  }
```

## Compiling binding tables

Internally, the lwAFTR uses the binding table in a compiled format.
When a lwAFTR is started, it will automatically compile its binding
table if needed.  However for large tables (millions of entries) this
can take a second or two, so it can still be useful to compile the
binding table ahead of time.

Use the `snabb lwaftr compile-binding-table` command to compile a
binding table ahead of time.  If you do this, you can use the
`snabb lwaftr control PID reload` command to tell the Snabb process
with the given *PID* to reload the table.
