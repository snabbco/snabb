# Continuous performance benchmarks: `cperf.sh`

The `cperf.sh` script can be used to run, compare and visualize how a set
of commits perform on a set of benchmarks. It is intended to be called
either manually, by a `post-merge` *Git hook* in an arbitrary *slave
repository* which is to be periodically updated (e.g. `git pull`) by a
*cronjob* or by *SnabbBot*.

## Usage

`cperf.sh` has two execution modes: `check` and `plot`. In `check` mode
`cperf.sh` accepts a set of *commit hashes*. It will run the *benchmark
scripts* for each commit hash and print the runs results. This mode is
suited to test and verify performance changes during development.

For instance if you branch off from e.g. `master` and want to test
performance improvements of your branch `performance-improved` you
would call `cperf.sh` like so:

```
$ cperf.sh check master performance-improved
Comparing with SAMPLESIZE=5
(benchmark, abbrev. sha1 sum, mean score, standard deviation)"
your_benchmark master 10 0.1
your_benchmark perfromance-improved 12 0.5
```

In `plot` mode `cperf.sh` will run your benchmark scripts for each *merge
commit* in a *commit range* as recognized by Git and record their results
continuously (e.g. benchmarks will *not* be run again for already
benchmarked commits). The results are then used to produce a linear graph
plot using *Gnuplot*. `plot` mode will populate a sub-directory
`results/` in `CPERFDIR` which will contain a file `benchmarks.png` (the
resulting plot). See *Requirements* below. For instance, to produce a
plot for the commits starting from `e14f3` you would call `cperf.sh` like
so:

```
cperf.sh plot HEAD...e14f3
```

In both modes `cperf.sh` will run each benchmark multiple times for each
commit hash in order to compute mean and standard derivation values. You
can adjust the `SAMPLESIZE` environment variable (which defaults to 5) in
order to control the number of times each benchmark is run.

## Requirements

You will need to create a dedicated directory for use by `cperf.sh` and
set the `CPERFDIR` environment variable to point to that directory. This
directory must contain a `benchmarks/` sub-directory which must contain
the *benchmark scripts* to be evaluated. A collection of *benchmark
scripts* for use with `cperf.sh` can be found in
[benchmarks/](benchmarks/).

## Interface

A *benchmark script* is defined to be an *executable program* that prints
a single floating point number to `stdout` and exits with a meaningful
status. E.g. if the benchmark fails, its *benchmark script* should exit
with a status `!= 0`.

## Note regarding the `loadgen` benchmark

The benchmark `src/scripts/cperf/benchmarks/loadgen-snabb-nic-guest` uses
the `BENCH_ENV` environment variable in order to locate the `bench_env`
scripts and defaults to `./src/scripts/bench_env`. Beware that by
default, due to the relative path to `bench_env`, a commit might be
checked out to be benchmarked, which doesn't even contain the `bench_env`
scripts (for instance). So make sure your benchmark environment isn't
tied to the repository you are benchmarking!
