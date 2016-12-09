# Troubleshooting: Common problems

## LwAftr performance reports zero MPPS/Gbps

**Problem:**

You run the lwAFTR with the `-v` argument to print out packet and bit rates, but it's all zeroes:

```
Time (s),IPv4 RX MPPS,IPv4 RX Gbps,IPv4 TX MPPS,IPv4 TX Gbps,IPv6 RX MPPS,IPv6 RX Gbps,IPv6 TX MPPS,IPv6 TX Gbps
0.999885,0.000000,0.000000,0.000000,0.000000,0.000000,0.000000,0.000000,0.000000
```

**Resolution:**

The lwaftr is running, but not receiving packets from the load generator.
Check that the load generator is running, and that the physical wiring is
between the interfaces the load generator is running on and the interfaces
that the lwaftr is running on, and that the `--v4` and `--v6` arguments
reflect the physical wiring, rather than being swapped.  If you have VLANs configured
and you are using Intel NICs, make sure the VLAN IDs are correct.

## Failed to lock NIC

**Problem:**

```
failed to lock /sys/bus/pci/devices/0000:01:00.0/resource0
lib/hardware/pci.lua:114: assertion failed!
stack traceback:
    core/main.lua:116: in function <core/main.lua:114>
    [C]: in function 'assert'
    lib/hardware/pci.lua:114: in function 'map_pci_memory'
    apps/intel/intel10g.lua:89: in function 'open'
    core/app.lua:165: in function <core/app.lua:162>
    core/app.lua:197: in function 'apply_config_actions'
    core/app.lua:110: in function 'configure'
    program/packetblaster/packetblaster.lua:51: in function 'run'
    core/main.lua:56: in function <core/main.lua:32>
    [C]: in function 'xpcall'
    core/main.lua:121: in main chunk
    [C]: at 0x0044e580
    [C]: in function 'pcall'
    core/startup.lua:1: in main chunk
    [C]: in function 'require'
    [string "require "core.startup""]:1: in main chunk
```

**Resolution:**

Something else is using the card on which locking failed. Kill that process or
choose a different card, and try again.

## NIC does not exist

**Problem:**

Running some tools with identifiers from `lspci` can result in the following:

```
lib/hardware/pci.lua:131: assertion failed!
```

Reminder: the lspci output will look something like this:

```bash
$ lspci | grep 82599
01:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+
01:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+
02:00.0 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+
02:00.1 Ethernet controller: Intel Corporation 82599ES 10-Gigabit SFI/SFP+
```

**Resolution:**

Many tools accept the short form of the PCI addresses (ie, _'01:00.0'_), but
some require them to match a filename in
`/sys/bus/pci/devices/`, such as `/sys/bus/pci/devices/0000:01:00.1` : in such
cases, you must write _'0000:01:00.0'_, with the appropriate prefix (_'0000:'_,
in this example).
