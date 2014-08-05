This directory contains scripts whose purpose is to continuously measure
performance by automatically running benchmarks and plotting their
results.

The `cperf.sh` script is intended to be called either manually or by a
`post-merge` *Git hook* in an arbitrary *slave repository* which is to be
periodically updated (e.g. `git pull`) by a *cronjob*.

`cperf.sh` executes *benchmark scripts* for each *merge commit* in a
*commit range* as recognized by Git and records their results
continuously (e.g. benchmarks will *not* be run again for already
benchmarked commits) which are then used to produce a linear graph plot
using *Gnuplot*. For instance, to produce a plot for the commits starting
from `e14f3` you would call `cperf.sh` like so: `cperf.sh HEAD...e14f3`

A *benchmark script* is defined to be an *executable program* that prints
a single floating point number to `stdout` and exits with a meaningful
status. E.g. if the benchmark fails, its *benchmark script* should exit
with a status `!= 0`. A collection of possible *benchmark scripts* can be
found in [benchmarks/](benchmarks/).

You will need to create a dedicated directory for use by `cperf.sh` and
set the `CPERFDIR` environment variable to point to that directory. This
directory must contain a `benchmarks/` sub-directory which must contain
the *benchmark scripts* to be evaluated. Another sub-directory `results/`
will be populated by `cperf-hook.sh`. It will contain a file
`benchmarks.png` which will be the resulting plot.

The `cperf.sh` will run each benchmark multiple times for each *merge
commit* in order to compute mean and standard derivation values. You can
adjust the `SAMPLESIZE` environment variable (which defaults to 5) in
order to control the number of times each benchmark is run.

## Note regarding the `loadgen` benchmark

The benchmark `src/scripts/cperf/benchmarks/loadgen-snabb-nic-guest` uses
the `BENCH_ENV` environment variable in order to locate the `bench_env`
scripts and defaults to `./src/scripts/bench_env`. Beware that by
default, due to the relative path to `bench_env`, a commit might be
checked out to be benchmarked, which doesn't even contain the `bench_env`
scripts (for instance). So make sure your benchmark environment isn't
tied to the repository you are benchmarking!
