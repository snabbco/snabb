# IPFIX and NetFlow apps

## IPFIX (apps.ipfix.ipfix)

The `IPFIX` app implements an RFC 7011 IPFIX "meter" and "exporter"
that records the flows present in incoming traffic and sends exported
UDP packets describing those flows to an external collector (not
included).  The exporter can produce output in either the standard RFC
7011 IPFIX format, or the older NetFlow v9 format from RFC 3954.

    DIAGRAM: IPFIX
                   +-----------+
                   |           |
    input     ---->*   IPFIX   *---->  output
                   |           |
                   +-----------+

See the `snabb ipfix probe` command-line interface for a program built
using this app.

### Configuration

The `IPFIX` app accepts a table as its configuration argument. The
following keys are defined:

— Key **idle_timeout**

*Optional*.  Number of seconds after which a flow should be considered
idle and available for expiry.  The default is 300 seconds.

— Key **active_timeout**

*Optional*.  Period at which an active, non-idle flow should produce
export records.  The default is 120 seconds.

— Key **flush_timeout**

*Optional*.  Maximum number of seconds after which queued data records
are exported.  If set to a positive value, data records are queued
until a flow export packet of maximum size according to the configured
**mtu** can be generated or **flush_timeout** seconds have passed
since the last export packet was generated, whichever occurs first.
If set to zero, data records are exported immediately after each scan
of the flow cache.  The default is 10 seconds.

— Key **cache_size**

*Optional*.  Initial size of flow tables, in terms of number of flows.
The default is 20000.

— Key **scan_time**

*Optional*.  The flow cache for every configured template is scanned
continously to check for entries eligible for export based on the
**idle_timeout** and **active_timeout** parameters.  The **scan_time**
determines the interval in seconds that a scan of the entire flow
cache will take.  The implementation uses a token bucket mechanism by
which access to the tables is distributed evenly over the time
interval.  The default is 10 seconds.

— Key **template_refresh_interval**

*Optional*.  Period at which to send template records over UDP.  The
default is 600 seconds.

— Key **ipfix_version**

*Optional*.  Version of IPFIX to export.  9 indicates legacy NetFlow
v9; 10 indicates RFC 7011 IPFIX.  The default is 10.

— Key **mtu**

*Optional*.  MTU for exported UDP packets.  The default is 512.

— Key **observation_domain**

*Optional*.  Observation domain tag to attach to all exported packets.
The default is 256.

— Key **exporter_ip**

*Required*, sadly.  The IPv4 address from which to send exported UDP
packets.

— Key **collector_ip**

*Required*.  The IPv4 address to which to send exported UDP packets.

— Key **collector_port**

*Required*.  The port on which the collector is listening for UDP
packets.

— Key **templates**

*Optional*.  The templates for flows being collected. 
See `apps/ipfix/README.templates.md` for more information.

### To-do list

Some ideas for things to hack on are below.

#### Limit the number of flows

As it is, if an attacker can create millions of flows, then our flow
set will expand to match (and never shrink).  Perhaps we should cap
the total size of the flow table.

#### Look up multiple keys in parallel

For large ctables, we can only do 7 or 8 million lookups per second if
we look up one key after another.  However if we do lookups in
parallel, then we can get 15 million or so, which would allow us to
reach 10Gbps line rate on 64-byte packets.

#### YANG schema to define IPFIX app configuration

We should try to model the configuration of the IPFIX app with a YANG
schema.  See RFC 6728 for some inspiration.

#### Use special-purpose internal links

The links that we use as internal buffers between parts of the IPFIX
app have some overhead as they have to update counters.  Perhaps we
should use a special-purpose data structure.

#### Use a monotonic timer

Currently internal flow start and end times use UNIX time.  This isn't
great for timers, but it does match what's specified in RFC 7011.
Could we switch to monotonic time?

#### Allow export to IPv6 collectors

We can collect IPv6 flows of course, but we only export to collectors
over IPv4 for the moment.

#### Allow packets to count towards multiple templates

Right now, routing a packet towards a flow set means no other flow set
can measure that packet.  Perhaps this should change.
