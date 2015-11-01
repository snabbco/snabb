# pflua

`pflua` is a high-performance network packet filtering library written
in Lua.  It supports filters written in
[pflang](https://github.com/Igalia/pflua/blob/master/doc/pflang.md), the
filter language of the popular
[tcpdump](https://www.wireshark.org/docs/man-pages/pcap-filter.html#DESCRIPTION)
tool.  It's really fast: to our knowledge, it's the fastest pflang
implementation out there, by a wide margin.  Read on for more details.

## Getting started

```shell
$ git clone --recursive https://github.com/Igalia/pflua.git
$ cd pflua; make             # Builds embedded LuaJIT
$ make check                 # Run builtin basic tests
```

## Using pflua

Pflua is a library; you need an application to drive it.

The most simple way to use pflua is filtering packets from a file
captured by `tcpdump`.  For example:

```
$ cd tools
$ ../deps/luajit/usr/local/bin/luajit pflua-filter \
    ../tests/data/v4.pcap /tmp/foo.pcap "ip"
Filtered 43/43 packets from ../tests/data/v4.pcap to /tmp/foo.pcap.
```

See the source of
[pflua-filter](https://github.com/Igalia/pflua/blob/master/tools/pflua-filter)
for more information.

Pflua was made to be integrated into the [Snabb
Switch](https://github.com/SnabbCo/snabbswitch/wiki) user-space
networking toolkit, also written in Lua.  A common deployment
environment for Snabb is within the host virtual machine of a
virtualized server, with Snabb having CPU affinity and complete control
over a high-performance 10Gbit NIC, which it then routes to guest VMs.
The administrator of such an environment might want to apply filters on
the kinds of traffic passing into and out of the guests.  To this end,
we plan on integrating pflua into Snabb so as to provide a pleasant,
expressive, high-performance filtering facility.

Given its high performance, it is also reasonable to deploy pflua on
gateway routers and load-balancers, within virtualized networking
appliances.

## Implementation

Pflua can compile pflang filters in two ways.

The default compilation pipeline is pure Lua.  First, a [custom
parser](https://github.com/Igalia/pflua/blob/master/src/pf/parse.lua)
produces a high-level AST of a pflang filter expression.  This AST is
[_lowered_](https://github.com/Igalia/pflua/blob/master/src/pf/expand.lua)
to a primitive AST, with a limited set of operators and ways in which
they can be combined.  This representation is then exhaustively
[optimized](https://github.com/Igalia/pflua/blob/master/src/pf/optimize.lua),
folding constants and tests, inferring ranges of expressions and packet
offset values, hoisting assertions that post-dominate success
continuations, etc.  We then lower to [A-normal
form](https://github.com/Igalia/pflua/blob/master/src/pf/anf.lua) to
give names to all intermediate values, perform common subexpression
elimination, then inline named values that are only used once.  We lower
further to [Static single
assignment](https://github.com/Igalia/pflua/blob/master/src/pf/ssa.lua)
to give names to all blocks, which allows us to perform control-flow
optimizations.  Finally, we
[residualize](https://github.com/Igalia/pflua/blob/master/src/pf/backend.lua)
Lua source code, using the control flow analysis from the SSA phase.

The resulting Lua function is a predicate of two parameters: the packet
as a `uint8_t*` pointer, and its length.  If the predicate is called
enough times, LuaJIT will kick in and optimize traces that run through
the function.  Pleasantly, this results in machine code whose structure
reflects the actual packets that the filter sees, as branches that are
never taken are not residualized at all.

The other compilation pipeline starts with bytecode for the [Berkeley
packet filter
VM](https://www.freebsd.org/cgi/man.cgi?query=bpf#FILTER_MACHINE).
Pflua can load up the `libpcap` library and use it to compile a pflang
expression to BPF.  In any case, whether you start from raw BPF or from
a pflang expression, the BPF is compiled directly to Lua source code,
which LuaJIT can gnaw on as it pleases.

We like the independence and optimization capabilities afforded by the
native pflang pipeline.  However, though pflua does a good job in
implementing pflang, it is inevitable that there may be bugs or
differences of implementation relative to what `libpcap` does.  For that
reason, the `libpcap`-to-bytecode pipeline can be a useful alternative
in some cases.

See the [doc](https://github.com/Igalia/pflua/blob/master/doc)
subdirectory for some examples of the Lua code generated for some simple
pflang filters using these two pipelines.

## Performance

To our knowledge, pflua is the fastest implementation of pflang out
there.  See https://github.com/Igalia/pflua-bench for our benchmarking
experiments and results.

Pflua can beat other implementations because:

* LuaJIT trace compilation results in machine code that reflects the
  actual traffic that your application sees

* Pflua can hoist and eliminate bounds checks, whereas [BPF is obligated to
  check that every packet access is valid](https://github.com/Igalia/pflua/blob/master/doc/pflang.md#packet-access)

* Pflua can work on data in network byte order, whereas BPF must
  convert to host byte order

* Pflua takes advantage of LuaJIT's register allocator and excellent
  optimizing compiler, whereas e.g. the Linux kernel JIT has a limited
  optimizer

## API documentation

None yet.  See
[pf.lua](https://github.com/Igalia/pflua/blob/master/src/pf.lua) for the
high-level `compile_filter` interface.

## Bugs

Check our [issue tracker](https://github.com/Igalia/pflua/issues)
for known bugs, and please file a bug if you find one.  Cheers :)

## Authors

Pflua was written by Katerina Barone-Adesi, Andy Wingo, Diego Pino, and
Javier Muñoz at [Igalia, S.L.](https://www.igalia.com/), as well as
Peter Melnichenko. Development of pflua was supported by Luke Gorrie at
[Snabb Gmbh](http://snabb.co/), purveyors of fine networking solutions. 
Thanks, Snabb!

Feedback is very welcome!  If you are interested in pflua in a Snabb
context, probably the best thing is to post a message to the
[snabb-devel](https://groups.google.com/forum/#!forum/snabb-devel)
group.  Or, if you like, you can contact Andy directly at
`wingo@igalia.com`.  If you have a problem that pflua can help solve,
let us know!
