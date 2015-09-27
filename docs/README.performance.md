# Tuning the performance of the lwaftr

## Adjust CPU frequency governor

Set the CPU frequency governor to _'performance'_:

```bash
for CPUFREQ in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
   [ -f $CPUFREQ ] || continue;
   echo -n performance > $CPUFREQ;
done
```
## Avoid fragmentation

Make sure that MTUs are set such that fragmentation is rare.

## Restart on a slow run

The system is built on a tracing JIT compiler. Work is in progress to reduce
variance, but occasionally there is a slow run:

```bash
for x in {1..10}; do
   # lwaftr-run is a thin wrapper around nic-ui
   lwaftr-run; done | lwstats.py
done
Initial v4 MPPS: min: 1.462, max: 2.159, avg: 2.014, stdev: 0.2865 (n=10)
Initial v4 Gbps: min: 5.965, max: 8.809, avg: 8.216, stdev: 1.1688 (n=10)
Initial v6 MPPS: min: 1.462, max: 2.019, avg: 1.902, stdev: 0.2278 (n=10)
Initial v6 Gbps: min: 6.900, max: 9.531, avg: 8.980, stdev: 1.0754 (n=10)
Final v4 MPPS: min: 1.486, max: 2.178, avg: 2.021, stdev: 0.2847 (n=10)
Final v4 Gbps: min: 6.062, max: 8.885, avg: 8.245, stdev: 1.1615 (n=10)
Final v6 MPPS: min: 1.486, max: 2.036, avg: 1.911, stdev: 0.2258 (n=10)
Final v6 Gbps: min: 7.012, max: 9.610, avg: 9.019, stdev: 1.0659 (n=10)
```

Runs which start slowly (for instance, at 1.4 MPPS), like other runs, speed up,
but they do not appear to converge on maximum speeds. If speed is an issue and
the lwaftr is underperforming, restarting it is recommended.
