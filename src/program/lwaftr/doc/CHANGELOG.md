# Change Log

## [2022.01.13]

### Notable changes

 * Support for XDP, AVF, and Mellanox drivers

 * Restore support for bump-in-the-wire operation

 * New updated lwAFTR YANG schema: `snabb-softwire-v3.yang`.
   lwAFTR can now operate on >2 CPU cores

 * Add statistics counters for ICMP, ARP, and NDP

 * Fragmenter/defragmenter can now handle padded packets (bug fix)

 * NDP app now sends correct neighbot advertisements (bug fix)

 * Fix a parsing bug in `lib.yang` where nested default values of leaves where not set

 * Fix a bug in `lib.numa` where it could not gracefully handle the inability to read a CPU performance governor

## [2019.06.02]

### Notable changes

 * Fix `snabb top` to correctly display per-worker statistics for
   instances of the lwAFTR running with receive-side scaling (RSS).
   See https://github.com/Igalia/snabb/pull/1237.

 * Fix a problem related to an interaction between late trace
   compilation and the ingress drop monitor.

   For context, Snabb uses LuaJIT, which is a just-in-time compiler.
   LuaJIT compiles program segments called traces.  Traces can jump to
   each other, and thereby form a graph.  The shape of the trace graph
   can have important performance impacts on a network function, but
   building the optimal graph shape is fundamentally hard.  Usually
   LuaJIT does a good job, but if a network function is dropping
   packets, Snabb's "ingress drop monitor" will ask LuaJIT to re-learn
   the graph of traces, in the hopes that this self-healing process will
   fix the packet loss situation.

   Unfortunately, the self-healing process has some poor interactions
   with so-called "long tail" traces -- traces that aren't taking an
   important amount of time, but which LuaJIT might decide to compile a
   few seconds into the running of a network function.  Compiling a
   trace can cause a latency spike and dropped packets, so the work of
   compiling these long-tail traces can in fact be interpreted as a
   packet loss situation, thereby triggering the self-healing process,
   leading to a pathologically repeating large packet loss situation.

   The right answer is for LuaJIT to avoid the latency cost for
   long-tail trace compilation.  While this might make long-tail traces
   run not as fast as they would if they were compiled, these traces
   take so little time anyway that it doesn't matter enough to pay the
   cost of trace compilation.

   See https://github.com/Igalia/snabb/pull/1236 and
   https://github.com/Igalia/snabb/pull/1239 for full details.

 * Disable profiling by default.  The version of LuaJIT that Snabb uses
   includes a facility for online profiling of network functions.  This
   facility is low-overhead but not no-overhead.  We have disabled it by
   default on the lwAFTR; it can be enabled by passing the --profile
   option.  See https://github.com/Igalia/snabb/pull/1238.

## [2019.06.01]

### Notable changes

 * Improve stability of receive-side scaling (RSS), in which multiple
   CPU cores can service traffic on the same NIC.  Previously, the
   lwAFTR had a pathology whereby a transient error condition that could
   cause one core to drop packets could then cause another core to
   attempt to perform self-healing by re-optimizing its code, which
   could then ping-pong back and cause the other core to try to
   self-heal, and on and on forever.  See
   https://github.com/Igalia/snabb/pull/1229 and
   https://github.com/snabbco/snabb/pull/1443 for more details.

 * Fix a problem whereby `snabb config add` would cause the lwAFTR to
   crash after a few thousand softwire additions.  See
   https://github.com/Igalia/snabb/pull/1228.

 * Update the `ieee-softwire` compatibility layer for the native
   `snabb-softwire-v2` Yang module, corresponding the latest changes in
   the Internet Draft,
   [`draft-ietf-softwire-yang-16`](https://datatracker.ietf.org/doc/draft-ietf-softwire-yang/16/).

 * Add counters and historical data records for how much memory a lwAFTR
   process uses over time, for use in on-line and post-mortem system
   diagnostics.  See https://github.com/Igalia/snabb/pull/1228 for
   details.

 * Add `snabb rrdcat` tool that can be used to identify when packet
   drops occured in the past.  See
   https://github.com/Igalia/snabb/pull/1225 for details.

 * Incorporate changes from the upstream [Snabb 2019.06
   "Deltadromeus"](https://github.com/snabbco/snabb/releases/tag/v2019.01)
   release.  This finally includes a switch over to RaptorJIT, which
   adds a number of on-line diagnostic tools that can be useful for
   troubleshooting performance problems in production.

## [2018.09.03]

### Features

 * Add new "revision" declaration to snabb-softwire-v2 YANG module,
   corresponding to addition of flow-label nodes back in version
   2018.09.01.  No changes to the schema otherwise.

 * Add new performance diagnostics that will print warnings for common
   system misconfigurations, such as missing `isolcpus` declarations or
   the use of power-saving CPU frequency scaling strategies.  These
   warnings detect conditions which are described in the performance
   tuning document.

     https://github.com/Igalia/snabb/pull/1212
     https://github.com/snabbco/snabb/blob/master/src/doc/performance-tuning.md

 * Improve `snabb lwaftr run --help` output.  Try it out!

### Bug fixes

 * Ingress drop monitor treats startup as part of grace period (10
   seconds by default), postponing the start of dropped packet detection
   until after the system has settled down.

     https://github.com/Igalia/snabb/issues/1216
     https://github.com/Igalia/snabb/pull/1217

 * Fix PCI/NUMA affinity diagnostics.

     https://github.com/Igalia/snabb/pull/1211

 * New YANG schema revisions cause Snabb to recompile configurations.

     https://github.com/Igalia/snabb/pull/1209

 * Re-enable NUMA binding on newer kernels (including the kernel used by
   Ubuntu 18.04).

     https://github.com/Igalia/snabb/pull/1207

## [2018.09.02]

### Features

* Add benchmarking test for 2 instances each with 2 queues (total of 4
  queues).

    https://github.com/Igalia/snabb/pull/1206

### Bug fixes

* Fixes compiling on GCC 8.1 relating to unsafe usage of `strncpy`.

    https://github.com/Igalia/snabb/pull/1193

* Fix bug where the next-hop counter reported an incorrect value. The
  ARP and NDP apps should now report the next-hop mac address when
  resolved.

    https://github.com/Igalia/snabb/pull/1204

* Fix bug in with ctables that caused a TABOV (table overflow) error.

    https://github.com/Igalia/snabb/pull/1200

* Fix a bug where the kernel could overwrite some of our memory
  due to giving an incorrect size being given in `get_mempolicy`. This
  could have caused a crash in certain situations. We're now
  allocating a mask of the correct size.

    https://github.com/Igalia/snabb/pull/1198

## [2018.09.01]

### Features

* Allow setting the IPv6 flow-label header field on ingress packets, allowing
  packets from different lwAFTR instances to be distinguished via the field.
  This adds a new `flow-label` field that can be used in YANG configurations.

    https://github.com/Igalia/snabb/pull/1183

* Next hop MAC addresses (`next-hop-macaddr-v4` and `next-hop-macaddr-v6`) are now
  shown in the `snabb top` view and are added to the YANG model so that they
  can be queried using `snabb config get-state`.

    https://github.com/Igalia/snabb/pull/1182

### Bug fixes

* Fix RRD recording for intel_mp stats counters. This fixes issues discovered
  with the statistics counter improvements from v2018.06.01 and improves the
  functionality of `snabb top`.

    https://github.com/Igalia/snabb/pull/1179

* Add a workaround for a bug in Linux kernel version 4.15.0-36 with memory
  binding to avoid segmentation faults.

    https://github.com/Igalia/snabb/pull/1187

* Improved error messages for invalid config files and for `snabb config`.

    https://github.com/Igalia/snabb/pull/1159
    https://github.com/Igalia/snabb/pull/1160

* Ensure leader process is bound to the correct NUMA node.

    https://github.com/Igalia/snabb/pull/1133

### Other enhancements from upstream

  * Integrates Snabb 2018.09 "Eggplant".

      https://github.com/snabbco/snabb/releases/tag/v2018.09

  * Includes updates to vhost-user driver, PMU support for some AMD CPUs,
    hash table improvements, a token bucket implementation, and support for
    time stamp counters.

Thanks to Alexander Gall, Ben Agricola, Luke Gorrie, Max Rottenkolber, and
kullanici0606 for their upstream contributions in this release.

## [2018.06.01]

### Features

* Add support for the `snabb lwaftr compile-config` command

* Improve the handling of statistics counters on the intel_mp NIC driver.
  This change makes queue counters show up for each NIC app in `snabb top`'s
  tree view.

### Bug fixes

* Fixes the conditions in which the lwAFTR uses a V4V6 splitter app. This
  fix should allow certain configurations with a different external & internal
  MAC to work correctly.

### Other enhancements from upstream

  * Adds software-based receive-side scaling (RSS) with an app

      https://github.com/snabbco/snabb/pull/1309

Thanks to Alexander Gall, Luke Gorrie, Max Rottenkolber, R. Matthew Emerson, and
hepeng for their upstream contributions in this release.

## [2018.04.02]

### Features

* Support influxdb format for `snabb config`.   Pass `--format influxdb` to
  `snabb config get-state` for output suitable for feeding to influxdb.

* Support larger binding tables.  The lwAFTR has now been tested with binding
  tables containing 40M entries.

* Support TAP interface for the lwAFTR.  This is useful when testing.

* Completely rewritten `snabb top`.  Notable changes include:
    * Shows all Snabb instances on the current machine, and worker-manager
      relationships.
    * Interactive interface for focussing in on specific Snabb processes.
    * New `top`-like summary view focussed on NIC throughput.
    * New tree view that can show all counters.
    * Support for historical flight-recorder data view.

  The new `snabb top` replaces `snabb snabbvmx top` as well.

  For more information, see `snabb top --help`:
    https://github.com/Igalia/snabb/tree/lwaftr/src/program/top

* Make the necessary lwAFTR changes to allow it to work with the new raptorJIT
  engine.  Note that this release does not include RaptorJIT yet; we are waiting
  on an upstream Snabb release that officially ships it.

* Add RRD support enabling storage of historical counter change rates.  The lwAFTR
  is configured to record counter change rates over 2-second windows for the last
  2 hours, 30-second windows for the last 24 hours, and 5-minute intervals over
  the last 7 days.  This data can be useful in an incident response context to
  find interesting operational events from the recent past.

* Improved support of several YANG data-types (leafref, ipv4-prefix and ipv6-prefix).

* Added support for YANG notifications.

### Bug fixes

* Fix display of invalid IP address when configured to use ARP to resolve the external
  interface's next hop.

* Relax NUMA policy to be less strict.  It used to be that if no NUMA-local memory was
  available for a Snabb worker, the worker would be silently killed.  The new behavior
  is to continue with some non-local memory.  This is a tradeoff that may result in lower
  performance when less NUMA-local memory is available, without warnings, but which
  prevents the operating system from silently killing Snabb workers.

* Fixed the TTL on ICMP ECHO reply packets, which no longer take their initial TTL from
  the corresponding ECHO request packets.

* Fix timezone offset in YANG alarms.

* Fix `snabb alarms listen` runtime error when running with wrong number of args.

* Fix incorrect argument parsing in `snabb loadtest find-limit` short form.

## [2018.04.01]

### Features

* Implement alarm shelving.  For documentation, see:

    https://github.com/Igalia/snabb/blob/lwaftr/src/program/alarms/README.md

* Extend `snabb loadtest find-limit` to handle multiple NICs, as in a
  lwAFTR bump-in-the-wire configuration.  For documentation, see:

    https://github.com/Igalia/snabb/blob/lwaftr/src/program/loadtest/find-limit/README

### Bug fixes

* Fix the `--format xpath` output for `snabb config get`; broken in
  the switch to the `snabb-softwire-v2` model, which exercises
  different kinds of paths.

* Fix alarm notification (accidentally disabled during refactor).
  Update documentation for `snabb alarms set-operator-state`.

* Fix lwAFTR to claim name when run with empty configuration (no
  workers).

* Fix `--verbose` lwAFTR mode when run on-a-stick.

* Improve reliability of unit and integration tests.

* Fix bug that can cause the lwAFTR to run out of file descriptors in
  some circumstances (https://github.com/snabbco/snabb/pull/1325).

* Fix documentation for ARP snabb component.

* Improve self-tests for unified Intel NIC driver.

* Improve reliability when piping `snabb config` output to files in the
  shell.  (https://github.com/snabbco/snabb/pull/1300).

* Make necessary modifications to support 64-bit Lua allocations, as
  will be the case with RaptorJIT.

### Other enhancements from upstream

From the
[2018.04](https://github.com/snabbco/snabb/releases/tag/v2018.04)
release:

* Add `snabb dnnsd` tool for browsing local DNS-SD records.  See:

    https://github.com/snabbco/snabb/blob/next/src/program/dnssd/README.md

* Add `snabb unhexdump` tool for converting packet dumps to pcap files.
  See:

    https://github.com/snabbco/snabb/blob/next/src/program/unhexdump/README

* Improve performance when using non-busy-wait mode.

* Add `Makefile` target to build Docker image.  See:

    https://github.com/snabbco/snabb/blob/next/README.md#snabb-container

* Improve output from `snabb top`.

Thanks to Marcel Wiget, Alexander Gall, Max Rottenkolber, and Luke
Gorrie for upstream work in this period.

## [2018.01.2.1]

### Features

* Added limit-finding loadtester.  See:

  https://github.com/Igalia/snabb/blob/lwaftr/src/program/loadtest/find-limit/README.inc

* Move "loadtest" command out of lwaftr.  Now the "loadtest" command consists of
  two subcommands: "transient" and "find-limit". Example:

  $ sudo ./snabb loadtest transient -D 1 -b 5e9 -s 0.2e9 \
    cap1.pcap "NIC 0" "NIC 1" 01:00.0 \
    cap2.pcap "NIC 1" "NIC 0" 01:00.1

  $ sudo ./snabb loadtest find-limit 01:00.0 cap1.pcap

### Bug fixes

* Fix next-hop discovery with multiple devices.  See:

    https://github.com/Igalia/snabb/issues/1014

* Improve effectiveness of property-based tests.

* Process tree runs data-plane processes with busywait=true by default

* Remove early lwAFTR NUMA affinity check.  The check was unnecessary since
  now ptree manager handles NUMA affinity and appropriate CPU selection.

* Sizes for "packetblaster lwaftr" are frame sizes.

## [2017.11.01]

* Add --trace option to "snabb lwaftr run", enabling a trace log of
  incoming RPC calls that can be later replayed.

* Fix excessive CPU and memory use when doing "snabb config get" of a
  large configuration.

## [2017.08.06]

* Update IETF yang model from `ietf-softwire` to `ietf-softwire-br`.  The
  lwAFTR no longer supports `ietf-softwire`.

## [2017.08.05]

* Documented `snabb alarms` facility.  See:

    https://github.com/Igalia/snabb/blob/lwaftr/src/program/alarms/README.md

* Implement specific alarms for lwAFTR.  See:

    https://github.com/Igalia/snabb/blob/lwaftr/src/program/lwaftr/doc/alarms.md

* Fix a bug when using RSS on on-a-stick workers with VMDq.

* Fix a bug when using ARP and NDP over RSS.

* Fix a bug when ARP received unexpected replies.

* Give `snabb-softwire-v2` the `snabb:softwire-v2` namespace instead of
  `snabb:lwaftr`, to differentiate the namespace from the older
  `snabb-softwire-v1` model.

* Change default YANG model exposed by lwAFTR to `ietf-softwire`.  The
  native `snabb-softwire-v2` model can of course be specified manually
  via `-s snabb-softwire-v2`.

## [2017.08.04]

* Enable RSS.  For full details, see:

    https://github.com/Igalia/snabb/blob/lwaftr/src/program/lwaftr/doc/configuration.md#multiple-devices

* Fix bugs related to dynamically adding and removing RSS workers.

* Extend `snabb config get-state` to understand multiple worker
  processes.  Counter values from worker processes are available
  individually and are also summed for the lwAFTR as a whole.

* Bug fixes to VMDq support in the new intel_mp driver.

## [2017.08.03]

* Fix on-a-stick mode for multiple worker processes.  The lwAFTR will now
  detect based on the configuration whether an lwAFTR instance is
  running in on-a-stick or bump-in-the-wire configuration.  The
  --on-a-stick, --v4, and --v6 arguments are still around if you want to
  use a single lwAFTR binding table, but run separate single-instance
  lwAFTR processes manually.

* The "compress", "purge", and "set-operator-state" commands have been
  moved from "snabb config" to "snabb alarms".  Documentation will be
  forthcoming; otherwise see their --help outputs.

## [2017.08.02]

* Adapt --cpu argument to "snabb lwaftr run" to take a range of
  available CPUs to dedicate to the forwarding plane.  To provision CPUs
  1 to 9 inclusive, run as --cpu=1-9.  Snabb will attempt to assign CPUs
  only from the local NUMA node of the PCI devices.

* Beginnings of the "snabb alarm" utility, extracting the alarms
  facilities that we had implemented as part of the "snabb config"
  utility as a separate binary.  This also removes the alarms-related
  components from the Snabb YANG model.

* Update the ietf-softwire translation layer for multiple worker
  instances.

* Dynamically add and remove worker instances via "snabb config".
  Documentation to come; follow
  https://github.com/Igalia/snabb/issues/953 for the summary of the
  multi-process deliverable.

## [2017.08.01]

* intel_mp work included in v2017.07.01 preview is now properly merged
  upstream.  The previous milestone release was on a side branch.

* The alarms facility now has support for set-operator-state, purge,
  compress, and get-status operations.  Note that the alarms code is in
  a state of flux currently; we are migrating alarms support out of the
  snabb-softwire-v2 YANG schema over the next few days.

* Fix some bugs with the snabb-softwire-v2 schema in which we were
  missing statements and namespace qualifiers.

* Fix bug in ingress drop monitor in which drops immediately following a
  JIT flush would cause further JIT flushes.

## [2017.07.01-318]

* The intel_mp driver has been brought up to feature parity with the
  intel10g one by adding support for VMDq mode. The changes support VMDq
  mode with RSS (64 VM pools with 2 RSS queues each) with MAC/VLAN
  filtering on the Intel 82599. For now, the driver just rejects VMDq
  mode on i210 and i350 NICs.  The added features include VLAN tag
  insertion and removal, MAC-based receive and transmit queue
  assignment, mirroring between pools/VFs, and support for rxcounter,
  txcounter, rate_limit, priority. The following combinations are
  supported: no VMDq nor RSS, VMDq only, RSS only.

* All network functions have been updated to use intel_mp instead of
  intel10g. The resulting performance has been checked to be as good as
  before the change.  The intel10g driver is temporarily being kept
  around as a fallback in case of regressions, and to give external apps
  some time to switch to intel_mp.

* Multiprocess in the data-plane.  If multiple instance are defined in the
  configuration file, the lwaftr will start those multiple instances.
  However, new ones cannot be added via `snabb config` nor can they be
  shutdown by removing them.

* Initial support for alarms.  NDP and ARP raise up an alarm if they cannot
  resolve an IP address.  The alarms is cleared up when the apps manage
  to resolve the IP addresses.  Alarms state can be consulted via
  `./snabb config get-state` program.

* Several apps have been refactored and moved out from lwaftr. Mainly
  the fragmentation and refactoring apps and the ARP and NDP apps.
  Several minor bugs have been fixed in these apps too, including packet
  corruption issues.

* Other minor bug fixes and improvements.

## [2017.07.01] - 2017-08-04

* New YANG schema snabb-softwire-v2 replaces old snabb-softwire-v1
  schema.

  The new schema has support for multiple worker processes running on
  different PCI interfaces, though this support has not yet landed in
  the data-plane itself.  See src/lib/yang/snabb-softwire-v2.lua for
  full details.

  Use "snabb lwaftr migrate-configuration" to migrate old
  configurations.  

* New version numbering scheme which includes the Snabb version the
  lwaftr is based off and a lwaftr specific version number which is
  reset upon merging a newer version of Snabb from upstream.

* Improve configuration migration system.

## [3.1.8] - 2017-03-10

* Retry ARP and NDP resolution indefinitely.

## [3.1.7] - 2017-01-20

* Reverts commit 86b9835 ("Remove end-addr in psid-map"), which 
  introduced a severe regression that caused high packet loss due
  to not maching softwires.

## [3.1.6] - 2017-01-19

* Add basic error reporting to snabb-softwire-v1.

* Add property-based testing for snabb config.

* Add socket support for "snabb config listen".

* Clean stale object files in program/lwaftr and program/snabbvmx.

* Fix "lwaftr query". Added selftest.

* Fix "snabb config remove" on arrays.

* Fix bug parsing empty strings in YANG parser.

* Fix tunnel-path-mtu and tunnel-payload-mtu in ietf-softwire.

* Respond to ping packets to internal and external interfaces when
  running in on-a-stick mode. Added test.

* Several improvements in lwaftrctl script (no screen command, connect
  via telnet, internet access in VM).

## [3.1.5] - 2016-12-09

 * Improve "snabb ps" output.  Processes with a "*" by them are
   listening for "snabb config" connections.

 * Fix race condition in multiprocess --reconfigurable mode.

 * Improve configuration change throughput.

 * Add "snabb config bench" utility for benchmarking configuration
   throughput.

 * Add automated "snabb config" tests.

 * Improve error message when --cpu setting was not possible.

## [3.1.4] - 2016-12-09

 * Fix memory corruption bug in main process of --reconfigurable "snabb
   lwaftr run" that would cause the dataplane to prematurely exit.

## [3.1.3] - 2016-12-08

 * Fix performance problem for --reconfigurable "snabb lwaftr run"
   wherein the main coordination process would also get scheduled on the
   data plane CPU.  Also re-enable ingress drop monitor and --real-time
   support for multiprocess lwaftr.

 * "snabb config --help" fixes.

 * Allow "snabb lwaftr query", "snabb lwaftr monitor", "snabbvmx query",
   and "snabbvmx top" to locate Snabb instances by name.

## [3.1.2] - 2016-12-07

 * Re-enabled multi-process mode for --reconfigurable "snabb lwaftr
   run", including support for "snabb config get-state".

 * Improve memory consumption when parsing big configurations, such as a
   binding table with a million entries.

 * Re-enable CSV-format statistics for "snabb lwaftr bench" and "snabb
   lwaftr run", which were disabled while we landed multiprocess
   support.

 * Fix "snabb ps --help".

## [3.1.1] - 2016-12-06

A hotfix to work around bugs in multiprocess support when using Intel
NICs.

 * Passing --reconfigurable to "snabb lwaftr run" now just uses a single
   process while we sort out multiprocess issues.

 * Fixed "snabb lwaftr query" and "snabb top", broken during
   refactoring.

## [3.1.0] - 2016-12-06

Adding "ietf-softwire" support, process separation between control and
the data plane, and some configuration file changes.

 * Passing --reconfigurable to "snabb lwaftr run" now forks off a
   dedicated data plane child process.  This removes the overhead of
   --reconfigurable that was present in previous releases.

 * Add support for ietf-softwire.  Pass the "-s ietf-softwire" to "snabb
   config" invocations to use this schema.

 * Add support for fast binding-table updates.  This is the first
   version since the YANG migration that can make fast updates to
   individual binding-table entries without causing the whole table to
   reload, via "snabb config add
   /softwire-config/binding-table/softwire".  See "snabb config"
   documentation for more on how to use "snabb config add" and "snabb
   config remove".

 * Add support for named lwAFTR instances.  Pass "--name foo" to the
   "snabb lwaftr run" command to have it claim a name on a machine.
   "snabb config" can identify the remote Snabb instance by name, which
   is often much more convenient than using the instance's PID.

 * Final tweaks to the YANG schema before deployment -- now the
   binding-table section is inside softwire-config, and the
   configuration file format is now enclosed in "softwire-config {...}".
   It used to be that only YANG "container" nodes which had "presence
   true;" would have corresponding data nodes; this was a mistake.  The
   new mapping where every container node from the YANG schema appears
   in the data more closely follows the YANG standard XML mapping that
   the XPath expressions are designed to operate over.

   Additionally, the "br" leaf inside "snabb-softwire-v1" lists is now a
   1-based index into the "br-address" leaf-list instead of a zero-based
   index.

   The "snabb lwaftr migrate-configation --from=3.0.1" command can
   migrate your 3.0.1 configuration files to the new format.  See "snabb
   lwaftr migrate-configuration --help" for more details.  The default
   "--from" version is "legacy", meaning pre-3.0 lwAFTR configurations.

## [3.0.1] - 2016-11-28

A release to finish "snabb config" features.

 * New "snabb config" commands "get-state", "add", "remove", and
   "listen".  See [the `snabb config` documentation](../../config/README.md)
   for full details.

 * The "get-state", "get", "set", "add", and "remove" "snabb config"
   commands can now take paths to indicate sub-configurations on which
   to operate.  This was documented before but not yet implemented.

## [3.0.0] - 2016-11-18

A change to migrate the lwAFTR to use a new YANG-based configuration.

 * New configuration format based on YANG.  To migrate old
   configurations, run "snabb lwaftr migrate-configation old.conf" on
   the old configuration.  See the [snabb-softwire-v1.yang
   schema](../../../lib/yang/snabb-softwire-v1.yang) or
   [configuration.md](./configuration.md) for full details
   on the new configuration format.

 * Send ICMPv6 unreachable messages from the most appropriate source address
   available (the one associated with a B4 if possible, or else the one the
   packet one is in reply to had as a destination.)

 * Add support for ARP resolution of the next hop on the external (IPv4)
   interface.

 * Add support for virtualized control planes via Snabb vMX.  See [the
   `snabbvmx` documentation](../../snabbvmx/doc/README.md) for more.

 * Add many more counters, used to diagnose the path that packets take
   in the lwAFTR.  See [counters.md](./counters.md) for
   more.

 * Add "snabb config" set of commands, to replace "snabb lwaftr control".
   See [the `snabb config` documentation](../../config/README.md) for
   full details.

 * Add initial support for being able to reconfigure an entire lwAFTR
   process while it is running, including changes that can add or remove
   ingresss or egress filters, change NIC settings, or the like.  Pass
   the `--reconfigurable` argument to `snabb lwaftr run`, then interact
   with the lwAFTR instance via `snabb config`.  Enabling this option
   currently has a small performance impact; this will go away in the
   next release.  A future release will also support efficient
   incremental binding-table updates.

 * Many updates from upstream Snabb.

## [2.10] - 2016-06-17

A Snabb NFV performance fix, which results in more reliable performance
when running any virtualized workload, including the lwAFTR.

 * Fix a situation in the NFV which caused runtime behavior that the JIT
   compiler did not handle well.  This fixes the situation where
   sometimes Snabb NFV would wedge itself into a very low-throughput
   state.

 * Disable jit.flush() mechanism in Snabb NFV, to remove a source of
   divergence with upstream Snabb NFV.  Ingress drops in the NFV are
   still detected and printed to the console, but as warnings.

 * Remove remaining sources of backpressure in the lwAFTR.

## [2.9] - 2016-06-09

A performance release, speeding up both the core lwaftr operations as
well as the support for running Snabb on virtualized interfaces.

 * Change Snabb representation of packets to have "headroom".
   Prepending a header to a packet, as when encapsulating a packet in a
   lightweight 4-over-6 softwire, can use this headroom instead of
   shifting the packet's payload around in memory.  Taking off a header,
   as in decapsulation, can likewise just adjust the amount of headroom.
   Likewise when sending packets to a host Snabb NFV the virtio system
   can place these headers in the headroom as well, instead of needing
   multiple virtio scatter-gather buffers.

 * Fix a bug in Snabb NFV by which it would mistakenly cache the Virtio
   features that it used when negotiating with QEMU at startup for the
   Snabb process.

 * Remove backpressure on the intel driver.  This means that if Snabb
   NFV is dropping packets at ingress, it is because Snabb NFV is too
   slow.  If it is dropping them on the NIC -> Virtio link, it is
   because the guest is too slow.

Note: this version of the lwaftr *needs* a fixed version of Snabb NFV to
run virtualized.  The patches are headed upstream, but for now, use the
Snabb NFV from this release instead of the ones from upstream.

## [2.8] - 2016-06-03

A bug-fix and documentation release.

 * Fix ability to load in ingress and egress filters from a file.  This
   feature was originally developed on our main branch and backported in
   v2.5, but the backport was missing a necessary fix from the main
   branch.

 * Update documentation on ingress and egress filtering, giving several
   examples.

 * Added performance analysis of the overhead of ingress and egress
   filtering.  See
   https://github.com/Igalia/snabb/blob/lwaftr_starfruit/src/program/lwaftr/doc/filters-performance.md.

 * Updated documentation for performance tuning.  See
   https://github.com/Igalia/snabb/blob/lwaftr_starfruit/src/program/lwaftr/doc/performance.md

 * Add a time-stamp for the JIT self-healing behavior, and adapt the
   message to be more helpful.

 * The "loadtest" command now separates reporting of drops that were
   because the load generator was not able to service its receive queue
   in time, and drops which originate in the remote tested process.

## [2.7] - 2016-05-19

A performance, feature, and bug-fix release.

 * Fix a situation where the JIT self-healing behavior introduced in
   v2.4 was not being triggered when VLANs were enabled.  Detecting when
   to re-train the JIT depends on information from the network card, and
   the Snabb Intel 82599 driver has two very different code paths
   depending on whether VLAN tagging is enabled or not.  Our fix that we
   introduced in v2.4 was only working if VLAN tagging was not enabled.
   The end result was that performance was not as reliably good as it
   should be.

 * Add the ability for the "loadtest" command to produce different load
   transient shapes.  See "snabb lwaftr loadtest --help" for more
   details.

## [2.6] - 2016-05-18

A bug fix release.

 * Fix ability to dump the running binding table to a text file.  Our
   previous fix in 2.5 assumed that we could find the original binding
   table on disk, but that is not always the case, for example if the
   binding table was changed or moved.

   On the bright side, the binding table dumping facility will now work
   even if the binding table is changed at run-time, which will be
   necessary once we start supporting incremental binding-table updates.

## [2.5] - 2016-05-13

A bug fix release.

 * Fix bug in the NDP implementation.  Before, the lwAFTR would respond
   to neighbor solicitations to any of the IPv6 addresses associated
   with tunnel endpoints, but not to the IPv6 address of the interface.
   This was exactly backwards and has been fixed.

 * Fix ability to dump the running binding table to a text file.  This
   had been fixed on the main development branch before v2.4 but we
   missed it when selecting the features to back-port to the 2.x release
   branch.

 * Add ability to read in ingress and egress filters from files.  If the
   filter value starts with a "<", it is interpreted as a file that
   should be read.  For example, `ipv6_egress_filter =
   <ipv6-egress-filter.txt"`.  See configuration.md.

## [2.4] - 2016-05-03

A bug fix, performance tuning, and documentation release.

 * Fix limitations and bugs in the NDP implementation.  Before, if no
   reply to the initial neighbor solicitation was received, neighbor
   discovery would fail.  Now, we retry solicitation for some number of
   seconds before giving up.  Relatedly, the NDP implementation now takes
   the MAC address from Ethernet header if reply does not contain it in
   the payload.

 * Automatically flush JIT if there are too many ingress packet drops.
   When the snabb breathe cycle runs, it usually doesn't drop any
   packets: packets pulled into the network are fully pushed through,
   with no residual data left in link buffers. However if the breathe()
   function takes too long, it's possible for it to miss incoming
   packets deposited in ingress ring buffers. That is usually the source
   of packet loss in a Snabb program.

   There are several things that can cause packet loss: the workload
   taking too long on average, and needing general optimization; the
   workload taking too long, but only during some fraction of breaths,
   for example due to GC or other sources of jitter; or, the workload
   was JIT-compiled with one incoming traffic pattern, but conditions
   have changed meaning that the JIT should re-learn the new
   patterns. The ingress drop monitor exists to counter this last
   reason. If the ingress drop monitor detects that the program is
   experiencing ingress drop, it will call jit.flush(), to force LuaJIT
   to re-learn the paths that are taken at run-time. It will avoid
   calling jit.flush() too often, in the face of sustained packet loss,
   by default flushing the JIT only once every 20 seconds.

 * Bug-fix backports from upstream Snabb: fix bugs when trying to use
   PCI devices whose names contain hexadecimal characters (from Pete
   Bristow), and include some documentation on performance tuning (by
   Marcel Wiget).

 * The load tester now works on line bitrates, including the ethernet
   protocol overhead (interframe spacing, prologues, and so on).

 * Add --cpu argument to "snabb lwaftr run", to set CPU affinity.  You
   can use --cpu instead of using "taskset", if you like.

 * Add --real-time argument to "snabb lwaftr run", to enable real-time
   scheduling.  This might be useful when troubleshooting, though in
   practice we have found that it does not have a significant effect on
   scheduling jitter, as the CPU affinity largely prevents the kernel
   from upsetting a Snabb process.

## [2.3] - 2016-02-17

A bug fix and performance improvement release.

 * Fix case in which TTL of ICMPv4 packets was not always being
   decremented.

 * Fix memory leaks when dropping packets due to 0 TTL, failed binding
   table lookup, or other errors that might cause ICMP error replies.

 * Fix hairpinning of ICMP error messages for non-existent IPv4 hosts.
   Before, these errors always were going out the public IPv4 interface
   instead of being hairpinned if needed.

 * Fix hairpinning of ICMP error messages for incoming IPv4 packets
   whose TTL is 0 or 1. Before, these errors always were going out the
   public IPv4 interface instead of being hairpinned if needed.

 * Fix hairpinning of ICMP error messages for packets with the DF bit
   that would cause fragmentation. Likewise these were always going out
   the public interface.

 * Allow B4s that have access to port 0 on their IPv4 address to be
   pinged from the internet or from a hairpinned B4, and to reply.  This
   enables a B4 with a whole IPv4 address to be pinged.  Having any
   reserved ports on an IPv4 address will prevent any B4 on that IPv4
   from being pinged, as reserved ports make port 0 unavailable.

 * Switch to stream in results from binding table lookups in batches of
   32 using optimized assembly code.  This increases performance
   substantially.

## [2.2] - 2016-02-11

Adds `--ring-buffer-size` argument to `snabb lwaftr run` which can
increase the receive queue size.  This won't solve packet loss when the
lwaftr is incapable of handling incoming throughput, but it might reduce
packet loss due to jitter in the `breathe()` times.  The default size is
512 packets; any power of 2 up to 32K is accepted.

Also, fix `snabb lwaftr run -v -v` (multiple `-v` options).  This will
periodically print packet loss statistics to the console.  This can
measure ingress packet loss as it is taken from the NIC counters.

## [2.1] - 2016-02-10

A bug-fix release to fix VLAN tagging/untagging when offloading this
operation to the 82599 hardware.

## [2.0] - 2016-02-09

A major release; see the documentation at
https://github.com/Igalia/snabb/tree/lwaftr_starfruit/src/program/lwaftr/doc
for more details on how to use all of these features.  Besides
bug-fixes, notable additions include:

 * Support for large binding tables with millions of softwires.  The
   binding table will be compiled to a binary format as needed, and may
   be compiled to a binary file ahead of time.

 * The configuration file syntax and the binding table syntax have
   changed once again.  We apologize for the inconvenience, but it
   really is for the better: now, address-sharing softwires can be
   specified directly using the PSID format.

 * Support for virtualized operation using `virtio-net`.

 * Support for discovery of next-hop L2 addresses on the B4 side via
   neighbor discovery.

 * Support for ingress and egress filters specified in `pflang`, the
   packet filtering language of language of `tcpdump`.

 * Ability to reload the binding table via a `snabb lwaftr control`
   command.

## [1.2] - 2015-12-10

Fix bugs related to VLAN tagging on port-restricted IP addresses.

Fix bugs related to ICMPv6 and hairpinning.

## [1.1] - 2015-11-25

This release has breaking configuration file changes for VLAN tags and
MTU sizes; see details below.

This release fixes VLAN tagging for outgoing ICMP packets. Outgoing ICMP
worked without VLANs, and now also works with them. Incoming ICMP
support looked broken as a side effect of the outgoing ICMP messages
with VLAN tags translated by the lwAftr not being valid. The primary
test suite has been upgraded to be equally comprehensive with and
without vlan support.

This release contains fragmentation support improvements. It fixes a
leak in IPv6 fragmentation reassembly, and enables IPv4 reassembly. For
best performance, networks should be configured to avoid fragmentation
as much as possible.

This release also allows putting a ```debug = true,``` line into
configuration files (ie, the same file where vlan tags are
specified). If this is done, verbose debug information is shown,
including at least one message every time a packet is received. This
mode is purely for troubleshooting, not benchmarking.

*Please note that there are two incompatible changes to the
 configuration file format.*

Firstly, the format for specifying VLAN tags has changed incompatibly.
Instead of doing:

```
v4_vlan_tag=C.htonl(0x81000444),
v6_vlan_tag=C.htonl(0x81000666),
```

the new format is:

```
v4_vlan_tag=0x444,
v6_vlan_tag=0x666,
```

We apologize for the inconvenience.

Secondly, the way to specify MTU sizes has also changed incompatibly.
Before, the `ipv4_mtu` and `ipv6_mtu` implicitly included the size for
the L2 header; now they do not, instead only measuring the packet size
from the start of the IPv4 or IPv6 header, respectively.

## [1.0] - 2015-10-01

### Added

- Static configuration of the provisioned set of subscribers and their mapping
to IPv4 addresses and port ranges from a text file (binding table).
- Static configuration of configurable options from a text file (lwaftr.conf).
- Feature-complete encapsulation and decapsulation of IPv4-in-IPv6.
- ICMPv4 handling: configurable as per RFC7596.
- ICMPv6 handling, as per RFC 2473.
- Feature-complete tunneling and traffic class mapping, with first-class support
for IPv4 packets containing UDP, TCP, and ICMP, as per RFCs 6333, 2473 and 2983.
- Feature-complete configurable error handling via ICMP messages, for example 
"destination unreachable", "host unreachable", "source address failed 
ingress/egress filter", and so on as specified.
- Association of multiple IPv6 addresses for an lwAFTR, as per draft-farrer-
softwire-br-multiendpoints.
- Full fragmentation handling, as per RFCs 6333 and 2473.
- Configurable (on/off) hairpinning support for B4-to-B4 packets.
- A static mechanism for rate-limiting ICMPv6 error messages.
- 4 million packets per second (4 MPPS) in the following testing configuration:
   - Two dedicated 10G NICs: one internet-facing and one subscriber facing (2 MPPS per NIC)
   - 550-byte packets on average.
   - A small binding table.
   - "Download"-like traffic that stresses encapsulation speed
   - Unfragmented packets
   - Unvirtualized lwAFTR process
   - A single configured IPv6 lwAFTR address.
- Source:
   - apps/lwaftr: Implementation of the lwAFTR.
- Programs:
   - src/program/snabb_lwaftr/bench: Used to get an idea of the raw speed of the
lwaftr without interaction with NICs
   - src/program/snabb_lwaftr/check: Used in the lwAFTR test suite. 
   - src/program/snabb_lwaftr/run: Runs the lwAFTR.
   - src/program/snabb_lwaftr/transient: Transmits packets from a PCAP-FILE to 
the corresponding PCI network adaptors. Starts at zero bits per second, ramping 
up to BITRATE bits per second in increments of STEP bits per second.
- Tests:
   - src/program/tests:
      - end-to-end/end-to-end.sh: Feature tests.
      - data: Different data samples, binding tables and lwAFTR configurations.
      - benchdata: Contains IPv4 and IPv6 pcap files of different sizes.
