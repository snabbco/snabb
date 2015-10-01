# Benchmarking

The instructions in [README.first.md](README.first.md) for running the lwaftr with a load 
generator are the instructions for the primary way to benchmark the lwaftr. 
In short:

To run two load generators and one lwaftr, you will need four interfaces. The 
following example assumes that `01:00.0` is cabled to `01:00.1`, and that 
`02:00.0` is cabled to `02:00.1`. Change the concrete pci devices specified to 
match the current system; See [README.first.md](README.first.md).

```bash
$ cd ${SNABB_LW_DIR} # The directory snabb-lwaftr is checked out into
$ sudo ./bin/snabb-lwaftr-blaster \
    --v4-pcap tests/apps/lwaftr/benchdata/ipv4-0550.pcap \
    --v6-pcap tests/apps/lwaftr/benchdata/ipv6-0550.pcap \
    --v4-pci 01:00.0 --v6-pci 02:00.0
```

Now, run the lwaftr itself:
```bash
$ sudo ./bin/snabb-lwaftr \
    --bt tests/apps/lwaftr/data/binding.table \
    --conf tests/apps/lwaftr/data/icmp_on_fail.conf \
    --v4-pci 01:00.1 --v6-pci 02:00.1
```

By varying the `--v4-pcap` and `--v6-pcap` arguments, the performance of the 
lwaftr can be benchmarked with different types of loads.

The contents of the pcap file are fed repeatedly through each NIC, to the 
lwaftr, by the load generator.

## Current performance

```bash
$ for x in {1..10}; do 
   sudo ./snabb snsh ./apps/lwaftr/nic_ui.lua \
      -v -D 5 \
      ../tests/apps/lwaftr/data/binding.table \
      ../tests/apps/lwaftr/data/icmp_on_fail.conf \
      0000:01:00.1 0000:02:00.1
  ; done | ../tests/apps/lwaftr/end-to-end/lwstats.py 
Initial v4 MPPS: min: 1.443, max: 2.153, avg: 1.875, stdev: 0.3520 (n=10)
Initial v4 Gbps: min: 5.887, max: 8.786, avg: 7.649, stdev: 1.4364 (n=10)
Initial v6 MPPS: min: 1.443, max: 2.014, avg: 1.791, stdev: 0.2802 (n=10)
Initial v6 Gbps: min: 6.810, max: 9.506, avg: 8.454, stdev: 1.3227 (n=10)
Final v4 MPPS: min: 1.468, max: 2.178, avg: 1.903, stdev: 0.3554 (n=10)
Final v4 Gbps: min: 5.991, max: 8.885, avg: 7.762, stdev: 1.4498 (n=10)
Final v6 MPPS: min: 1.468, max: 2.036, avg: 1.818, stdev: 0.2821 (n=10)
Final v6 Gbps: min: 6.930, max: 9.609, avg: 8.578, stdev: 1.3315 (n=10)
```

This does 10 runs of 5 seconds each, and reports on the _minimum_/_maximum_/
_average_ performance of the first second (_Initial_) and last second (_Final_).
Performance tends to increase with time, although this effect disappears with 
the highest speeds.

The MPPS and Gbps speeds are relative to the outgoing interface, which is why 
the same MPPS figures correspond to different Gbps. Both interfaces are being 
fed with 550 byte packets, but the outgoing v6 ones are 590 bytes (due to 
encapsulation), while the outgoing v4 ones are 510 bytes (they have undergone 
decapsulation).

Maximum speeds on all interfaces during both initial and final runs were over 
2 MPPS.

## Understanding current performance

Performance varies within and between runs. It tends to increase with time,
although this effect disappears with the highest speeds.

### Performance of a slow run

```bash
$ sudo ./snabb snsh ./apps/lwaftr/nic_ui.lua \
    -v -D 25 \
    ../tests/apps/lwaftr/data/binding.table \
    ../tests/ps/lwaftr/data/icmp_on_fail.conf \
    0000:01:00.1 0000:02:00.1
v4_stats: 1.476 MPPS, 6.021 Gbps.
v6_stats: 1.476 MPPS, 6.965 Gbps.
v4_stats: 1.500 MPPS, 6.121 Gbps.
v6_stats: 1.500 MPPS, 7.082 Gbps.
v4_stats: 1.499 MPPS, 6.118 Gbps.
v6_stats: 1.499 MPPS, 7.077 Gbps.
v4_stats: 1.503 MPPS, 6.130 Gbps.
v6_stats: 1.503 MPPS, 7.092 Gbps.
v4_stats: 1.503 MPPS, 6.131 Gbps.
v6_stats: 1.503 MPPS, 7.093 Gbps.
v4_stats: 1.503 MPPS, 6.130 Gbps.
v6_stats: 1.503 MPPS, 7.092 Gbps.
v4_stats: 1.503 MPPS, 6.130 Gbps.
v6_stats: 1.503 MPPS, 7.092 Gbps.
v4_stats: 1.502 MPPS, 6.127 Gbps.
v6_stats: 1.502 MPPS, 7.088 Gbps.
v4_stats: 1.501 MPPS, 6.123 Gbps.
v6_stats: 1.501 MPPS, 7.083 Gbps.
v4_stats: 1.498 MPPS, 6.112 Gbps.
v6_stats: 1.498 MPPS, 7.071 Gbps.
v4_stats: 1.499 MPPS, 6.115 Gbps.
v6_stats: 1.499 MPPS, 7.074 Gbps.
v4_stats: 1.502 MPPS, 6.128 Gbps.
v6_stats: 1.502 MPPS, 7.089 Gbps.
v4_stats: 1.502 MPPS, 6.128 Gbps.
v6_stats: 1.502 MPPS, 7.090 Gbps.
```

This needs further investigation. Note that the speed trends upward with time.

### Performance of a mixed run

```bash
$ sudo ./snabb snsh ./apps/lwaftr/nic_ui.lua \
    -v -D 25 \
    ../tests/apps/lwaftr/data/binding.table \
    ../tests/apps/lwaftr/data/icmp_on_fail.conf \
    0000:01:00.1 0000:02:00.1
v4_stats: 2.142 MPPS, 8.740 Gbps.
v6_stats: 2.003 MPPS, 9.456 Gbps.
v4_stats: 2.178 MPPS, 8.885 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.885 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.884 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.885 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.885 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.177 MPPS, 8.884 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 1.720 MPPS, 7.019 Gbps.
v6_stats: 1.656 MPPS, 7.815 Gbps.
v4_stats: 1.635 MPPS, 6.669 Gbps.
v6_stats: 1.585 MPPS, 7.479 Gbps.
v4_stats: 1.339 MPPS, 5.462 Gbps.
v6_stats: 1.339 MPPS, 6.318 Gbps.
v4_stats: 1.338 MPPS, 5.460 Gbps.
v6_stats: 1.338 MPPS, 6.317 Gbps.
v4_stats: 2.177 MPPS, 8.883 Gbps.
v6_stats: 2.036 MPPS, 9.610 Gbps.
```

The speed dips and recovers; this has not yet been investigated.

### Performance of a steady fast run

```bash
$ sudo ./snabb snsh ./apps/lwaftr/nic_ui.lua \
    -v -D 25 \
    ../tests/apps/lwaftr/data/binding.table \
    ../tests/ps/lwaftr/data/icmp_on_fail.conf \
    0000:01:00.1 0000:02:00.1
v4_stats: 2.150 MPPS, 8.773 Gbps.
v6_stats: 2.011 MPPS, 9.492 Gbps.
v4_stats: 2.178 MPPS, 8.885 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.885 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.884 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.177 MPPS, 8.884 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.885 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.885 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.885 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.885 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.885 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.177 MPPS, 8.884 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.885 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.885 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.885 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.885 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.885 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.884 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
v4_stats: 2.178 MPPS, 8.885 Gbps.
v6_stats: 2.036 MPPS, 9.609 Gbps.
```

This is a fast, solid run, with extremely consistent speeds.

## Approximate benchmarking, without physical NICs

To get an idea of the raw speed of the lwaftr without interaction with NICs, 
or check the impact of changes on a development machine that may not have 
Intel 82599 NICs, `snabb-lwaftr bench` may be used:

```bash
$ sudo ./snabb-lwaftr bench \
    ../tests/apps/lwaftr/data/binding.table \
    ../tests/apps/lwaftr/data/icmp_on_fail.conf \
    ../tests/apps/lwaftr/benchdata/ipv4-0550.pcap \
    ../tests/apps/lwaftr/benchdata/ipv6-0550.pcap
statisticsv6: 4.246 MPPS, 20.043 Gbps.
statisticsv4: 4.246 MPPS, 17.325 Gbps.
statisticsv6: 4.237 MPPS, 19.999 Gbps.
statisticsv4: 4.237 MPPS, 17.287 Gbps.
statisticsv6: 4.266 MPPS, 20.133 Gbps.
statisticsv4: 4.266 MPPS, 17.403 Gbps.
statisticsv6: 4.238 MPPS, 20.002 Gbps.
statisticsv4: 4.238 MPPS, 17.290 Gbps.
statisticsv6: 4.149 MPPS, 19.584 Gbps.
statisticsv4: 4.149 MPPS, 16.928 Gbps.
```

The processing is not limited to 10 Gbps, as no NIC hardware is involved.
