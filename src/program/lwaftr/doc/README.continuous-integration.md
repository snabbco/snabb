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

(The following uses the `lwaftr-nic` jobset as an example.)

The parameters of each jobset are defined on its [configuration tab]
(https://hydra.snabb.co/jobset/igalia/lwaftr-nic#tabs-configuration). Each
lwAftr branch under test is pointed to a pair of parameters, named `snabbXname`
and `snabbXsrc`, where `X` is an uppercase letter.

A curve is drawn on each report graph for each `snabbXname/snabbXsrc` pair,
labeled with the `snabbXname` value, and showing benchmarks of the `snabbXsrc`
branch.

## Reports

Jobsets list executed jobs on the [Jobs tab]
(https://hydra.snabb.co/jobset/igalia/lwaftr-nic#tabs-jobs). Click on the
[reports.lwaftr](https://hydra.snabb.co/job/igalia/lwaftr-nic/reports.lwaftr)
job, and then on a successful build (indicated by a green mark). In the "Build
products" section, click on "report.html".

The report has three sections:

- "Initialization": a summary of the benchmark output data;
- "Line graph": graphs for the various quantities in the output data;
- "Density plot": the distribution of output data for each quantity.

Each graph shows several curves, one per branch, highlighting the performance
differences among them.
