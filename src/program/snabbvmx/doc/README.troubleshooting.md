# Testing & troubleshooting

## Troubleshooting

### Troubleshooting lwAFTR

If traffic managed by the lwAFTR component is not responding as expected: packets
that should get decapsulate don't match a softwire, some packets are dropped,
traffic don't get in, etc, it's convenient to inspect lwAFTR counters to
diagnose the problem.  The Snabb's `lwaftr query` tool can be used to obtain
the counter values of a lwAFTR instance.

The Snabb's lwAFTR manual includes a chapter covering troubleshooting and counters,
with charts about the most common lwAFTR paths (encapsulation, decapsulation,
hairpinning, etc).  Please refer to that guide for troubleshooting the
lwAFTR logic (chapter 8 - Counters).

The manual also includes a section covering troubleshooting related with running
a lwAFTR instance.  This information can be useful in case of running the lwAFTR
as a standalone application and not via SnabbVMX.

### Troubleshooting SnabbVMX

This section covers the most common problems when running a SnabbVMX instance.

#### Cannot start the SnabbVMX instance

`Description`: When running a snabbvmx instance, an error reports `failed to lock
<NIC>`.

```bash
$ sudo ./snabb snabbvmx lwaftr --conf snabbvmx-lwaftr.cfg --id xe1 \
   --pci 0000:81:00.0 --mac 02:AA:AA:AA:AA:AA
core/main.lua:26: failed to lock /sys/bus/pci/devices/0000:81:00.0/resource0
stack traceback:
        core/main.lua:137: in function <core/main.lua:135>
        [C]: in function 'error'
        core/main.lua:26: in function 'assert'
        lib/hardware/pci.lua:143: in function 'map_pci_memory_locked'
```

`Solution`: This error happens when trying to run a Snabb program, in this case
SnabbVMX, on a NIC which is already in use.  Please check that there's no other
Snabb instance running on the same NIC (in this example, `0000:81:00.0`).

#### SnabbVMX running but not receiving traffic

`Description`: a `snabbvmx lwaftr` instance is running on a NIC, but `snabbvmx
top` reports that the SnabbVMX instance is receiving no traffic.

`Solution`: This is a common problem which might be originated by various causes.

1. If no traffic is received at all, the most likely cause is that the selected
lwAFTR binding table contains no valid softwires for incoming traffic.

2. Another possible cause is that SnabbVMX is running with dynamic nexthop
resolution, but dynamic nexthop resolution is not working.

#### Dynamic nexthop resolution is not working

`Description`: SnabbVMX is running with dynamic nexthop resolution, but no traffic
is leaving the lwAFTR.

`Solution`: Check that SnabbVMX is indeed running with dynamic nexthop resolution.
SnabbVMX's configuration file should have a `cache_refresh_interval` attribute
set to a value higher than 0.

```bash
ipv6_interface = {
   cache_refresh_interval = 1,
},
ipv4_interface = {
   ipv4_address = "10.0.1.1",
   cache_refresh_interval = 1,
},
```

If that's correct, the likely cause is that refreshment packets are not arriving
to the VM.  A refreshment packet is a packet that is sent periodically to the VM
to trigger nexthop cache resolution.

Packets might not be arriving to the VM because there's no VM actually running.
Was SnabbVMX started with a sock address?

```bash
sudo ./snabb snabbvmx lwaftr --id xe0 --conf snabbvmx-lwaftr-xe0.cfg
   --pci 02:00.0 --mac 02:aa:aa:aa:aa:aa --sock /tmp/vh1a.sock
```

If that's correct, another cause is that the selected MAC address (02:aa:aa:
aa:aa:aa in the example above) doesn't match the lwAFTR's configuration
attributes `aftr_mac_inet_side` and `aftr_mac_b4_side`.  Check the bottom of
the next section for more details.

#### SnabbVMX doesn't respond to IPv4 or IPV6 pings

`Description`: Trying to ping SnabbVMX on one of its IPv4 or IPv6 interfaces gets
no response.

`Solution`: Check that the target address is indeed the lwAFTR IPV4 and IPv6
address. Steps:

1. Open the selected SnabbVMX configuration file and go to its lwAFTR
configuration.
2. Check that the values of attributes `aftr_ipv6_ip` and `aftr_ipv4_ip` are
equals to the target address.

In case the address is correct, check that the SnabbVMX MAC address is the same
as `aftr_mac_inet_side` and `aftr_mac_b4_side`.  In SnabbVMX these values must
be the same, as there's a single NIC for both interfaces.

SnabbVMX should have been initiated with this MAC address value.  Search a
SnabbVMX process to see its command line parameters:

```bash
$ ps aux | grep snabbvmx
root     16115  0.0  0.0 133856  2936 pts/2    S+   22:39   0:00
   sudo ./snabb snabbvmx lwaftr --conf snabbvmx-lwaftr.cfg --id xe1
   --pci 0000:81:00.0 --mac 02:AA:AA:AA:AA:AA
```

#### SnabbVMX decapsulation path works but not encapsulation

`Description`: `snabb top` reports that the running SnabbVMX instance is
able to decapsulate packets, but not to encapsulate them.

```
  lwaftr:
    in-ipv4-packets: 1,531,201,100 PPS
    in-ipv6-packets: 0 PPS
    out-ipv4-packets: 0 PPS
    out-ipv6-packets: 1,531,201,100 PPS
```

`Solution`: If the decapsulation path works, then the lwAFTR is able to
decapsulate IPv6 packets coming from the B4: therefore the IPv4 source address
and source port of the IPv6 encapsulated packet match a softwire in the
binding table. However, when a packet arrives to the lwAFTR from the Internet
the packet is dropped, thus RX is 0 in lwaftr_v4.

The destination address and port of an incoming IPv4 packet should match a
softwire in the binding table.  What's the destination address and port of
incoming packets? Is the lwAFTR using a VLAN tag for its IPv4 interface? Most
likely incoming packets are not VLAN tagged.  Check if SnabbVMX's config file
has a VLAN tag set.  Also check if the referred lwAFTR config file has a VLAN
tag set.

What's the MTU size of the IPv4 interface?  Check that value in SnabbVMX and
lwAFTR configuration file.  If the MTU size is too small, packets will be
fragmented.  A extremely small MTU size and disabled fragmentation will cause
most of the packets to be dropped.

#### Packets don't get mirrored

`Description`: You're using a tap interface for monitoring lwAFTR packets but
nothing gets in.

`Solution`:

1. Check that you're running SnabbVMX with mirroring enabled.
2. Check that you're running `lwaftr monitor` pointing to the IPv4 address you
would like to monitor.  For testing purposes, set `lwaftr monitor` to `all`.
3. Check that your tap interface is up.

---

## Tests overview

Tests are useful to detect bugs in the `lwaftr` or `snabbvmx` and double-check that
everything is working as expected.

**preparation**
- have tcpdump, snabb or vmxlwaftr installed.
- should work on xeon or i7; will fail on Celeron chips
- hugepages : Ensure hugepages is set in sysctl
"vm.nr_hugepages = 5" in sysctl.conf
If using vmxlwaftr, then this is done by the scripts automatically

**Test types**
SnabbVMX features three types of tests:

* Lua selftests: Unit tests for several modules
(**apps/lwaftr/V4V6.lua** and **apps/lwaftr/nh_fwd.lua**).
* Bash selftests: Complex setups to test certain functionality (**program/
snabbvmx/tests/selftest.sh** and **program/snabbvmx/tests/nexthop/
selftest.sh**).
* End-to-end tests: Specific end-to-end test cases for SnabbVMX
(**program/snabbvmx/tests/end-to-end/selftest.sh**).

Usually Lua selftests and Bash selftests won't fail, as these tests must
successfully pass on every Snabb deliverable.  End-to-end tests won't fail
either, but it's interesting to learn how to add new SnabbVMX's end-to-end
tests to diagnose potential bugs.

All these tests are run by Snabb's Continuous Integration subsystem (snabb-bot).
The tests can also be run when executing **make test** (only if the Snabb source
is available).


### Make tests

```bash
$ sudo make test
TEST      apps.lwaftr.V4V6
TEST      apps.lwaftr.nh_fwd
...
TEST      program/snabbvmx/tests/selftest.sh
SKIPPED   testlog/program.snabbvmx.tests.selftest.sh
TEST      program/snabbvmx/tests/nexthop/selftest.sh
SKIPPED   testlog/program.snabbvmx.tests.nexthop.selftest.sh
...
TEST      program/snabbvmx/tests/end-to-end/selftest.sh
...
TEST      program/lwaftr/tests/end-to-end/selftest.sh
TEST      program/lwaftr/tests/soaktest/selftest.sh
```
Execution of a test can return 3 values:

* **TEST**: The test run successfully (exit code 0)
* **SKIPPED**: The test was skipped, usually because it needs access to
a physical NIC and its PCI address was not set up (exit code 43).
* **ERROR**: The test finished unexpectedly (exit code > 0 and != 43).

### Lua selftests

* **apps/lwaftr/V4V6.lua**: Builds customized IPv4 and IPv4-in-IPv6 packets,
and joins the packets to a single link (*test_join*) or splits the packets
to two different links (*test_split*).
* **apps/lwaftr/nh_fwd.lua**: Builds customized packets and test the 3 code
paths of next-hop forwarder: *from-wire-to-{lwaftr, vm}*,
*from-vm-to-{lwaftr, wire}*, *from-lwaftr-to-{vm, wire}*.

To run an individual Lua module (app, program or library) selftest:

```
$ sudo ./snabb snsh -t apps.lwaftr.V4V6
V4V6: selftest
OK
```

### Bash selftests

* **program/snabbvmx/tests/selftest.sh**: Tests Ping, ARP and NDP resolution
by the VM.
* **program/snabbvmx/tests/nexthop/selfttest.sh**: Tests nexthop resolution
by the VM.

For instance, the result of executing `snabbvmx/tests/selftest.sh` would be the
following:

```bash
$ sudo SNABB_PCI0=83:00.0 SNABB_PCI1=03:00.0 \
       program/snabbvmx/tests/selftest.sh

Launch Snabbvmx
Waiting for VM listening on telnet port 5000 to get ready... [OK]
Ping to lwAFTR inet side: OK
Ping to lwAFTR inet side (Good VLAN): OK
Ping to lwAFTR inet side (Bad VLAN): OK
Ping to lwAFTR B4 side: OK
Ping to lwAFTR B4 side (Good VLAN): OK
Ping to lwAFTR B4 side (Bad VLAN): OK
ARP request to lwAFTR: OK
ARP request to lwAFTR (Good VLAN): OK
ARP request to lwAFTR (Bad VLAN): OK
NDP request to lwAFTR: OK
NDP request to lwAFTR (Good VLAN): OK
NDP request to lwAFTR (Bad VLAN): OK
```

NOTE: To successfully run the test, the `SNABB_PCI0` and `SNABB_PCI1` cards must
be wired to each other.

The test goes through several steps:

1. Run **SnabbVMX** on NIC **SNABB_PCI0**.
2. Run **QEMU**.
3. Configure VM eth0 interface with MAC, IPv4/IPv6 address, ARP & NDP cache table.
4. Run **tcpreplay** on NIC SNABB_PCI1. Sample packets reach the VM.
5. Outgoing packets from the VM are mirrored to a tap interface (tap0).
6. Capture **responses on tap0** and compare them with the expected results.

The input data, as well as the expected outputs, is at `program/snabbvmx/tests/pcap`.

The test validates VLAN packets too.  However, there are no VLAN tagged versions
of the expected outputs.  The reason is that it is the NIC which tags and untags
a packet.  Since the packet did not leave the NIC yet, they come out from the VM
untagged.

```bash
$ tcpdump -qns 0 -ter good/arp-request-to-lwAFTR.pcap
reading from file arp-request-to-lwAFTR.pcap, link-type EN10MB (Ethernet)
52:54:00:00:00:01 > ff:ff:ff:ff:ff:ff, 802.1Q, length 46: vlan 333, p 0,
ethertype ARP, Request who-has 10.0.1.1 tell 10.0.1.100, length 28
```

The other bash selftest validates correct resolution of the nexthop by the VM.

```bash
$ sudo SNABB_PCI0=03:00.0 SNABB_PCI1=83:00.0 \
       program/snabbvmx/tests/nexthop/selftest.sh
Waiting for VM listening on telnet port 5000 to get ready... [OK]
Resolved MAC inet side: 6a:34:99:99:99:99 [OK]
Resolved MAC inet side: 4f:12:99:99:99:99 [OK]
```

The test goes through several steps:

1. Run SnabbVMX on SNABB_PCI0.
2. Run VM.
3. Send packets in loop to SNABB_PCI1 for 10 seconds. Packets reach the VM.

```bash
$ packetblaster replay -D 10 $PCAP_INPUT/v4v6-256.pcap $SNABB_PCI1
```

4. Retrieve nexthop values (snabbvmx nexthop).
5. Compare to expected values.
6. Timeout if 10 seconds elapsed.

NOTE: Currently the test is not working correctly: the returned MAC should be
`02:99:99:99:99:99`.


## Crafting and running end-to-end tests

### Brief steps

1) Run the interactive check with "-r" param to derive the counters and out.pcaps:

```
$ snabb snabbvmx check -r  ./CONF.cfg "./V4-IN.PCAP" "./V6-IN.PCAP" \
  "./outv4.pcap" "./outv6.pcap" COUNTERS.lua`
```

2) Place derived counters.lua in "snabb/src/program/snabbvmx/tests/end-to-end/data/counters".

3) Place derived and expected out.pcaps in "snabb/src/program/snabbvmx/tests/end-to-end/data".

4) Edit the "test_env.sh" in snabb/src/program/snabbvmx/tests/end-to-end
to have the test scripted.

5) Run the scripted test:

```
$ snabb/src/program/snabbvmx/tests/end-to-end$ sudo ./end-to-end.sh
```

### How the system test works in detail

The way the test system works is by passing the input IPv4/IPv6 packets (via
pre-recorded pcap-files) to the lwAFTR and comparing the expected packet output
(pcap-file) to the packet output that the lwAFTR has generated.

The optional counters file is compared too to the actual counters file obtained
after running the test. This is being reflected in snabbvmx check syntax:

`CONF V4-IN.PCAP V6-IN.PCAP V4-OUT.PCAP V6-OUT.PCAP [COUNTERS.LUA]`

V4-OUT.PCAP, V6-OUT.PCAP and COUNTERS.LUA are expected outputs. These outputs are
compared to files stored temporarily in /tmp/endoutv4.pcap, /tmp/endoutv6.pcap
and /tmp/counters.lua. These temporary files are the actual output produced by
the lwAFTR after running a test. In order for a test to pass, the actual output
must match the expected outputs. So it's not only that the counters file should
match, but also the output .pcap files. (read: if a counters.lua file is
provided, then it must still match the V4-OUT.PCAP and V6-OUT.PCAP).

**lwaftr vs snabbvmx**

As both lwaftr and snabbvmx provide a different functionality and use different
config-files, both the lwaftr and snabbvmx have their dedicated end-to-end tests.

Although SnabbVMX works on a single interface, `snabbvmx check` requires that
the packet split (IPv4 / IPv6) is already done and provides a split output too.

Snabb's lwAFTR includes an end-to-end test suite counterpart.  In most cases,
the lwAFTR's correctness will be tested via Snabb's lwAFTR end-to-end tests.
However, since SnabbVMX uses a different configuration file, the network design
that it brings up might be slightly different than Snabb's lwAFTR. For instance,
Snabb's lwAFTR fragmentation is always active, while in SnabbVMX it is an optional
argument, either for IPV4 and IPv6 interfaces.

Modifications in the app chain might execute the lwAFTR's data plane in a different
way, bringing up conditions that were not covered by the lwAFTR's data-plane.
For this reason a specific end-to-end test suite was added, covering specifics
needs of SnabbVMX.  If a bug is found, its resolution will most likely happen
in Snabb's lwAFTR code, resulting in the addition of a new test to the lwAFTR's
test suite.


**lwaftr**

```
cd src/program/lwaftr/tests/end-to-end
```

**snabbvmx**

```
cd src/program/snabbvmx/tests/end-to-end
```

**interactive and scripted tests**

To develop an end-to-end tests, it's recommended to first run it interactively.
Once the config-files, pcaps and counters are derived, the test can be added to
the scripted tests in test_env.sh.

**interactive**

To run an interactive end-to-end test, either use the snabbvmx or lwaftr app. Keep
in mind that the test is running with the app specified (lwaftr or snabbvmx).

- snabb snabbvmx check.
- snabb lwaftr check.

**end-to-end interactive usage**

```
$ sudo ./snabb snabbvmx check
Usage: check [-r] CONF V4-IN.PCAP V6-IN.PCAP V4-OUT.PCAP V6-OUT.PCAP
                  [COUNTERS.LUA]
```

Parameters:

- **CONF**: SnabbVMX (icmp_snabbvmx-lwaftr-xe.cfg) or lwaftr
(icmp_snabbvmx-lwaftr-xe1.conf) configuration file.
- **V4-IN.PCAP**: Incoming IPv4 packets (from Internet).
- **V6-IN.PCAP**: Incoming IPv6 packets (from b4).
- **V4-OUT.PCAP**: Outgoing IPv4 packets (to Internet, decapsulated).
- **V6-OUT.PCAP**: Outgoing IPv6 packets (to b4, encapsulated)
- **[COUNTERS.LUA]**: Lua file with counter values. Will be regenerated via
[-r] param.

## How to run SnabbVMX interactive end-to-end test

If you detected an error in the lwAFTR, the first step is to obtain the
configuration file that SnabbVMX was using, as well as a copy of lwAFTR's
configuration and binding table.  With that information and knowing the error
report (ping to lwAFTR but it doesn't reply, valid softwire packet doesn't get
decapsulated, etc), you craft a hand-made packet that meets the testing case.

**Obtaining the config-files**

To run a test, the following config-files are required:

- binding-table: binding_table.txt.s.
- lwaftr conf: snabbvmx-lwaftr-xe[0-9].conf.
- snabbvmx cfg: snabbvmx-lwaftr-xe[0-9].cfg.

If you are running lwaftr check, then snabbvmx config-file
(snabbvmx-lwaftr-xe[0-9].cfg) is not required.

It is fine to copy or manually craft the config-files.

A running snabbvmx can be used as well to copy the config-files from the running
container. To obtain the used config-files from the running container, either
run the collect-support-infos.sh (https://github.com/mwiget/vmxlwaftr/blob/
igalia/SUPPORT-INFO.md) or execute a shell within the dockers container and copy
configs and binding-table from the /tmp directory.

Note: The `snabbvmx check` application is just using a single interface. If the
running container consists of two or more snabb-instances, then just take one
of them for when running the check.

**Script collect-support-infos.sh**

```
lab@ubuntu1:~/vmxlwaftr/tests$ ./collect-support-infos.sh lwaftr3-16.2R3
collecting data in container lwaftr3-16.2R3 ...
tar: Removing leading `/' from member names
tar: stats.xml: Cannot stat: No such file or directory
tar: Removing leading `../' from member names
tar: Exiting with failure status due to previous errors
transferring data from the container to host ...
-rw-r--r-- 1 lab lab 22700552 Nov  8 13:35 support-info-20161108-1335.tgz

lab@ubuntu1:~/vmxlwaftr/tests/t1$ tar -tvzf support-info-20161108-1335.tgz
-rw-rw-r-- root/root        55 2016-10-31 14:07 VERSION
-rw-r--r-- root/root      1166 2016-11-08 13:35 snabb_xe0.log
-rw-r--r-- root/root      1167 2016-11-08 13:35 snabb_xe1.log
-rw-r--r-- root/root        18 2016-11-04 15:36 mac_xe0
-rw-r--r-- root/root        18 2016-11-04 15:36 mac_xe1
-rw-r--r-- root/root        16 2016-11-04 15:36 pci_xe0
-rw-r--r-- root/root        16 2016-11-04 15:36 pci_xe1
-rw-r--r-- root/root  86560454 2016-11-08 13:35 binding_table.txt
-rw-r--r-- root/root      7132 2016-11-08 13:35 sysinfo.txt
-rw-r--r-- root/root 139505710 2016-11-04 15:41 binding_table.txt.s
-rw-r--r-- root/root       297 2016-11-04 15:42 snabbvmx-lwaftr-xe0.cfg
-rw-r--r-- root/root       297 2016-11-04 15:42 snabbvmx-lwaftr-xe1.cfg
-rw-r--r-- root/root       377 2016-11-04 15:42 test-snabbvmx-lwaftr-xe0.cfg
-rw-r--r-- root/root       377 2016-11-04 15:43 test-snabbvmx-lwaftr-xe1.cfg
-rw-r--r-- root/root       452 2016-11-04 15:42 snabbvmx-lwaftr-xe0.conf
-rw-r--r-- root/root       377 2016-11-04 15:42 snabbvmx-lwaftr-xe1.conf
-rw-r--r-- root/root      1239 2016-11-08 13:35 config.new
-rw-r--r-- root/root      1699 2016-11-08 13:35 config.new1
-rw-r--r-- root/root      1239 2016-11-04 15:41 config.old
-rwxr-xr-x root/root       167 2016-11-04 15:42 test_snabb_lwaftr_xe0.sh
-rwxr-xr-x root/root       167 2016-11-04 15:43 test_snabb_lwaftr_xe1.sh
-rwxr-xr-x root/root       204 2016-11-04 15:42 test_snabb_snabbvmx_xe0.sh
-rwxr-xr-x root/root       204 2016-11-04 15:43 test_snabb_snabbvmx_xe1.sh
-rw-r--r-- root/root     33499 2016-11-04 15:36 config_drive/vmm-config.tgz
-rw-r--r-- root/root      3126 2016-11-04 15:36 root/.bashrc
-rwxr-xr-x root/root   2707019 2016-10-31 14:06 usr/local/bin/snabb
```

**Config-files within /tmp inside docker container**

The snabbvmx config-files can be derived from the container's shell as well
directly within the /tmp directory.

```
lab@ubuntu1:~/vmxlwaftr/tests/t1$ docker exec -ti lwaftr3-16.2R3 bash
pid 2654's current affinity mask: fffff
pid 2654's new affinity mask: ff3ff
root@8f5d057b8298:/# ls /tmp/
binding_table.txt           config.new
binding_table.txt.s         config.new1
binding_table.txt.s.new     config.old
binding_table.txt.s.o       junos-vmx.qcow2
mac_xe                      snabb_xe0.log
mac_xe                      snabb_xe1.log
pci_xe                      snabbvmx-lwaftr-xe0.cfg
pci_xe                      snabbvmx-lwaftr-xe0.conf
snabbvmx-lwaftr-xe1.cfg     test-snabbvmx-lwaftr-xe0.cfg
snabbvmx-lwaftr-xe1.conf    test-snabbvmx-lwaftr-xe1.cfg
support-info.tgz            test_snabb_lwaftr_xe0.sh
sysinfo.txt                 test_snabb_lwaftr_xe1.sh
test_snabb_snabbvmx_xe0.sh  vhost_features_xe1.socket
test_snabb_snabbvmx_xe1.sh  vmxhdd.img
vFPC-20160922.img           xe0.socket
vhost_features_xe0.socket   xe1.socket
```

Note: Press Ctrl-P + Ctrl-Q to exit the containers shell.

**Some adoption of config-files is required**

The advantage of snabbvmx is the dynamic next-hop resolution via Junos. When
running the lwaftr or snabbvmx app standalone, then the next-hop resolution
via Junos is missing. The config-files are required to get modified for static
next-hop configuration.

**Config as derived from a running vmxlwaftr container**

```
lab@ubuntu1:~/vmxlwaftr/tests/t1$ cat snabbvmx-lwaftr-xe1.cfg
return {
  lwaftr = "snabbvmx-lwaftr-xe1.conf",
  settings = {
  },
  ipv6_interface = {
    ipv6_address = "",
    cache_refresh_interval = 1,
    fragmentation = false,
  },
  ipv4_interface = {
    ipv4_address = "192.168.5.2",
    cache_refresh_interval = 1,
    fragmentation = false,
  },
}
```

**Adopted static next-hop configuration to use with vmxlwaftr**

To change configuration for static next-hop, below changes are required:

- cache_refresh_interval = 0 (turns off next-hop learning via Junos).
- mac_address (thats the own/self mac-address fo lwaftr).
- next_hop_mac (next-hop mac to send the packets to).

Note: The snabbvmx config icmp_snabbvmx-lwaftr-xe1.cfg references the
snabb-configuration file icmp_snabbvmx-lwaftr-xe1.conf via the "lwaftr" directive.
When running "snabbvmx check" then both the lwaftr and the snabbvmx config-files
must be provided.

```
cd snabb/src/program/snabbvmx/tests/end-to-end/data$
cat icmp_snabbvmx-lwaftr-xe1.cfg
return {
  lwaftr = "icmp_snabbvmx-lwaftr-xe1.conf",
  settings = {
  },
  ipv6_interface = {
    ipv6_address = "",
    cache_refresh_interval = 0, # Set this to 0
    fragmentation = false,
    mac_address = "02:cf:69:15:81:01",  # lwaftr's own mac address. input pcap match this mac
    next_hop_mac = "90:e2:ba:94:2a:bc", # the next-hop mac to use for outgoing packets
  },
  ipv4_interface = {
    ipv4_address = "192.168.5.2",
    cache_refresh_interval = 0,   <<< set this to 0
    fragmentation = false,
    mac_address = "02:cf:69:15:81:01",  # lwaftr's own mac address. input pcap match this mac
    next_hop_mac = "90:e2:ba:94:2a:bc", # the next-hop mac to use for outgoing packets
  },
}
```

**The input pcaps**

The snabb "check" app requires one or two input pcaps. It is OK to:

- Only feed V4-IN.PCAP.
- Only feed the V6-IN.PCAP.
- Feed both V4-IN.PCAP and V6-IN.PCAP.

Note for interactive tests: When only feeding one pcap as input, then the other
empty pcap must be the "empty.pcap" (src/program/snabbvmx/tests/end-to-end/
data/empty.pcap) and not an empty string like "".

```
cd snabb/src/program/snabbvmx/tests/end-to-end/data$
$ file empty.pcap
empty.pcap: tcpdump capture file (little-endian) - version 2.4 (Ethernet,
capture length 65535)
$ tcpdump -r empty.pcap
reading from file empty.pcap, link-type EN10MB (Ethernet)
```

**Sample icmp-ipv4-in.pcap**

For any input pcap it makes sense to keep it short - ideally a single packet to
check correctness of the lwaftr. The input packet "11:26:07.168372 IP
10.0.1.100.53 > 10.10.0.0.1024: [|domain]" is matching the binding-table for PSID=1.

```
cd snabb/src/program/snabbvmx/tests/end-to-end/data$
$ cat cg-binding_table.txt.s
psid_map {
  10.10.0.0  {psid_length=6, shift=10}
  10.10.0.1  {psid_length=6, shift=10}
  10.10.0.10 {psid_length=6, shift=10}
}
br_addresses {
  2a02:587:f700::100,
}
softwires {
  { ipv4=10.10.0.0, psid=1, b4=2a02:587:f710::40 }
  { ipv4=10.10.0.0, psid=2, b4=2a02:587:f710::41 }
  { ipv4=10.10.0.0, psid=3, b4=2a02:587:f710::42 }
  { ipv4=10.10.0.0, psid=4, b4=2a02:587:f710::43 }
}

lab@cgrafubuntu2:~$ tcpdump -n -r ipv4-in.pcap
reading from file ipv4-in.pcap, link-type EN10MB (Ethernet)
11:26:07.168372 IP 10.0.1.100.53 > 10.10.0.0.1024: [|domain]
```

**Running the interactive check**

The interactive check is performed via `snabb snabbvmx check -r`. Using the
"-r" param instructs the check to generate the counters and out.pcap files.
As there is no IPv6 input, the "empty.pcap" is configured.

```
sudo ~/vmx-docker-lwaftr/snabb/src/snabb snabbvmx check -r   \
   ./snabbvmx-lwaftr-xe1.cfg "./ipv4-in.pcap" "./empty.pcap" \
   "./outv4.pcap" "./outv6.pcap" test.lua
loading compiled binding table from ./binding_table.txt.s.o
compiled binding table ./binding_table.txt.s.o is up to date.
nh_fwd4: cache_refresh_interval set to 0 seconds
nh_fwd4: static next_hop_mac 90:e2:ba:94:2a:bc
nh_fwd6: cache_refresh_interval set to 0 seconds
nh_fwd6: static next_hop_mac 90:e2:ba:94:2a:bc
done
```

**Results**

The -r flag is set, as such the resulting counters file test.lua and the
out.pcap files are  generated freshly.  The results below show a correct
processing of the lwatr:

- The counters-file lists one IPv4 packet as input as the input-packet matches
the binding-table.
- One IPv6 packet output.
- Outv4.pcap is empty.
- Outv6.pcap shows the resulting encapsulated lw4o6 packet.

```
$ cd snabb/src/program/snabbvmx/tests/end-to-end/data
$ cat test.lua
return {
   ["in-ipv4-bytes"] = 42,
   ["in-ipv4-packets"] = 1,
   ["out-ipv6-bytes"] = 82,
   ["out-ipv6-packets"] = 1,
}
$ tcpdump -n -r outv4.pcap
reading from file outv4.pcap, link-type EN10MB (Ethernet)

$ tcpdump -n -r outv6.pcap
reading from file outv6.pcap, link-type EN10MB (Ethernet)
01:00:00.000000 IP6 2a02:587:f700::100 > 2a02:587:f710::400:
IP 10.0.1.100.53 > 10.10.0.0.1024: [|domain]
```

**Summary of interactive check**

At this stage the interactive test is finished.  The following is defined:

- lwaftr and snabbvmx configs.
- Binding-table.
- Input pcaps.
- Expected resulting counters and out.pcap.

With known input and results, the test can now be added to the end-to-end.sh
script to be executed with all other tests to ensure snabbvmx behaves as it
should. Furthermore, this end-to-end procedure can be ideally used to report
issues!

Tip: Packets always arrive only in one interface, but the output might be empty
or non-empty for both IPv4 and IPv6.

## Adding the sample-test towards the scripted end-to-end tests

### In short

- Place counter file and out.pcaps into correct directory.
- Edit "test_env.sh" and add the test.
- Run the test.

### Detailed steps

Step 1. Directory structure:

Place out.pcap into the data-drectory

```
snabb/src/program/snabbvmx/tests/end-to-end/data
```

Place counter-file into counters-drectory

```
snabb/src/program/snabbvmx/tests/end-to-end/data/counters
```

Files in **program/snabbvmx/tests/end-to-end/**:

* **test_env.sh**: Contains the test cases.
* **core-end-to-end.sh**: Runs the test cases using **snabbvmx check**.
* **data/**: Directory containing sample pcap input, expected pcap output,
configuration files and binding tables.
* **end-to-end.sh**: Runs **core-end-to-end.sh** on normal packets.
* **end-to-end-vlan.sh**: Runs **core-end-to-end.sh** on VLAN packets.
* **selftest.sh**: Runs both **end-to-end.sh** and **end-to-end-vlan.sh**

Step 2. Adding the sample test:

All tests are defined in the "test_env.sh" file.  This "test_env.sh" file has
to be edited to include the sample test.  The check app always checks the
provided data to decide if the test is successful or not:

- If the optional counters-file is provided, then it must match.
- The resulting out.pcap files must always match.

Step 3. Pass-criteria without the optional counters.lua file:

```
src/program/snabbvmx/tests/end-to-end$ vi test_env.sh
...
# Contains an array of test cases.
#
# A test case is a group of 7 data fields, structured as 3 rows:
#  - "test_name"
#  - "snabbvmx_conf" "v4_in.pcap" "v6_in.pcap" "v4_out.pcap" "v6_out.pcap"
#  - "counters"
#
# Notice spaces and new lines are not taken into account.
TEST_DATA=(
    "sample test"
    "snabbvmx-lwaftr-xe1.cfg" "ipv4-in.pcap" "" "" "outv6.pcap"
    ""

    "IPv6 fragments and fragmentation is off"
    "snabbvmx-lwaftr-xe1.cfg" "" "regressiontest-signedntohl-frags.pcap" "" ""
    "drop-all-ipv6-fragments.lua"
)
```

```
src/program/snabbvmx/tests/end-to-end$ sudo ./end-to-end.sh
Testing: sample test
loading compiled binding table from data/binding_table.txt.s.o
compiled binding table data/binding_table.txt.s.o is up to date.
nh_fwd4: cache_refresh_interval set to 0 seconds
nh_fwd4: static next_hop_mac 90:e2:ba:94:2a:bc
nh_fwd6: cache_refresh_interval set to 0 seconds
nh_fwd6: static next_hop_mac 90:e2:ba:94:2a:bc
done
Test passed
Testing: IPv6 fragments and fragmentation is off
loading compiled binding table from data/binding_table.txt.s.o
compiled binding table data/binding_table.txt.s.o is up to date.
nh_fwd4: cache_refresh_interval set to 0 seconds
nh_fwd4: static next_hop_mac 90:e2:ba:94:2a:bc
nh_fwd6: cache_refresh_interval set to 0 seconds
nh_fwd6: static next_hop_mac 90:e2:ba:94:2a:bc
done
Test passed
All end-to-end lwAFTR tests passed.
```

If the counters file shall be taken into consideration as well (e.g. to count
dropped frames), then just one line needs to be changed from "" to the counters
file "test.lua".

```
$ cd snabb/src/program/snabbvmx/tests/end-to-end
$ vi test_env.sh
```

```
"sample test"
"snabbvmx-lwaftr-xe1.cfg" "ipv4-in.pcap" "" "" "outv6.pcap"
"test.lua"
```
