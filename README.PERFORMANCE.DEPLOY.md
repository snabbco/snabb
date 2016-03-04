# Maximizing deployment performance

For maximum performance, several hardware and operating system parameters need
to be tuned. Note that this document is only on tuning for deployment
performance, not on how to write performant Snabb code.

- Disable IOMMU (TODO: note what ways to to do this work, and which do not).
  Rationale: it causes various problems; at worst, it causes 100% packet loss.

- Disable hyperthreading (TODO: note what ways to do this actually work).
  Rationale: hyperthreading causes latency spikes, which cause packet loss.

- Bios settings should be set to maximum performance, not power-saving.
  Details are BIOS-specific.

- CPU governor settings should be performance, rather than ondemand or powersaving.
  (TODO: put the command here)

- irqbalance should be disabled.
  It is on by default in Ubuntu and off by default on NixOS).
  (TODO: document how here.)

There are also several NUMA-related factors that should be tuned.

- Make sure the Snabb process is on the same NUMA node as the card.
  (QEMU/docker/VhostUser notes here?)
  
  You can check which cores are on which numa node with numactl -H.

  (Document using numastat -c processname, taskset, ...)

Other factors:

* Tune the ring-buffer size; the default is too small. (TODO: details).

