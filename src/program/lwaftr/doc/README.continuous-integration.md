# Continuous integration

The Snabb project has a continuous integration lab - the SnabbLab - described
in [the Snabb docs](http://snabbco.github.io/#snabblab). The lab servers are
used for checking correctness and performance of Snabb branches, before merging
them into the master branch.

The servers are handled by [Hydra](https://nixos.org/hydra/), the continuous
integration system of the [NixOS](http://nixos.org/) operating system, which
the servers run.

The code in the [snabblab-nixos](https://github.com/snabblab/snabblab-nixos)
repo defines the Hydra jobs that are run by [Snabb's Hydra instance]
(https://hydra.snabb.co/). It also defines the reports generated from the job
results.

## lwAftr benchmarks

[One of the projects](https://hydra.snabb.co/project/igalia) on Snabb's Hydra
instance hosts the lwAftr CI benchmarks. Three jobsets are currently defined:

- [lwaftr-bare](https://hydra.snabb.co/jobset/igalia/lwaftr-bare) runs the
  `snabb lwaftr bench` command, which executes lwAftr benchmarks with no
  interaction with physical NICs;
- [lwaftr-nic](https://hydra.snabb.co/jobset/igalia/lwaftr-nic) runs the
  `snabb lwaftr loadtest` and `snabb lwaftr run` commands: the first command
  generates network traffic to a physical NIC, which is then received by
  another NIC and processed by the lwAftr instance launched by the second
  command;
- [lwaftr-virt](https://hydra.snabb.co/jobset/igalia/lwaftr-nic) is similar to
  lwaftr-nic, but runs the lwAftr commands in a virtualized environment. [TBC]

## Jobset parameters

(The following uses the temporary `zzz-lwaftr-nic-dev` jobset as an example.)

The parameters of each jobset are defined on its [configuration tab]
(https://hydra.snabb.co/jobset/igalia/zzz-lwaftr-nic-dev#tabs-configuration).

Each lwAftr branch under test is pointed to by a pair of parameters, named
`snabbXname` and `snabbXsrc`, where `X` is an uppercase letter. A curve is
drawn on each report graph for each `snabbXname/snabbXsrc` pair, labeled with
the `snabbXname` value, and showing benchmarks of the `snabbXsrc` branch.

The `conf` parameter selects a configuration file from within the
`src/program/lwaftr/tests/data/` directory.

The `ipv4PCap` and `ipv6PCap` parameters select data files from within the
`src/program/lwaftr/tests/data/` directory.

The `duration` parameter states the amount of time, in seconds, that each test
will be run.

The `times` parameter states how many times each test will be run.

## Reports

Jobsets list executed jobs on the [Jobs tab]
(https://hydra.snabb.co/jobset/igalia/zzz-lwaftr-nic-dev#tabs-jobs). Click on
the [reports.lwaftr]
(https://hydra.snabb.co/job/igalia/zzz-lwaftr-nic-dev/reports.lwaftr) job, and
then on a successful build (indicated by a green mark). In the "Build products"
section, click on "report.html".

The report has three sections:

- "Initialization": a summary of the benchmark output data;
- "Line graph": graphs for the various quantities in the output data;
- "Density plot": the distribution of output data for each quantity.

Each graph shows several curves, one per branch, highlighting the performance
differences among them.
