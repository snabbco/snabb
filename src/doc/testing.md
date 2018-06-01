# Testing Snabb


## Running the Test Suite with Docker

The easiest way to setup a Snabb test environment is to use a
Docker image that already contains everything needed, such as
`eugeneia/snabb-nfv-test`:

```
docker pull eugeneia/snabb-nfv-test
cd snabb/src
scripts/dock.sh "(cd .. && make)" # Build within container
scripts/dock.sh make test
```

You can also test Snabb in an alternative Docker image by
exporting `SNABB_TEST_IMAGE`.


## Running the Test Suite directly on the Host

You will have to ensure that the dependencies are met. If you want to the
NFV selftest, additional test assets are required. First you have to
install QEMU on the host. Then you need to to download the correct VM
images used by the test suite from
[http://lab1.snabb.co:2008/~max/assets/]:

```
mkdir ~/.test_env
curl http://lab1.snabb.co:2008/~max/assets/vm-ubuntu-trusty-14.04-dpdk-snabb.tar.gz \
     | tar xvz -C ~/.test_env/
```

Once you have installed QEMU and populated `~/test_env` you can run the
test suite:

```
cd snabb/src
sudo make test
```


## Running Benchmarks

Benchmarking Snabb is just one command away:

```
cd snabb/src
make benchmarks # Prefix with “scripts/dock.sh ” to run in container.
```

In addition to the environment variables described below, `make
benchmarks` accepts another parameter: `SNABB_PERF_SAMPLESIZE`. By
default, `make benchmarks` will run each benchmark once and print their
results. When `SNABB_PERF_SAMPLESIZE` is set to a positive integer, `make
benchmarks` will instead run each benchmark as many times and print their
results as mean value and standard deviation.

The available benchmarks can be found under `src/benchmarks/`. You can
inspect the individual benchmarks and/or run them individually, too.


## Environment Variables

Some Snabb tests require configuration through environment
variables. Described below are the environment variables used throughout
the tests:

* `SNABB_PCI0`, `SNABB_PCI1`—PCI addresses of two wired NICs. These are
  the only variables required to run most of the test suite.

* `SNABB_PCI_INTEL0`, `SNABB_PCI_INTEL1`—Optional PCI addresses of two
  wired Intel NICs. These are preferred over `SNABB_PCI0` and
  `SNABB_PCI1` in Intel specific tests. Some Intel specific tests (namely
  packetblaster based benchmarks) will be skipped if these are not set.

* `SNABB_PCI_INTEL1G0`, `SNABB_PCI_INTEL1G1`—Optional PCI addresses for use in
  Intel1G selftest.

* `SNABB_PCI_SOLARFLARE0`, `SNABB_PCI_SOLARFLARE1`—Optional PCI addresses
  of two wired Solarflare NICs. These are preferred over `SNABB_PCI0` and
  `SNABB_PCI1` in Solarflare specific tests.

* `SNABB_TELNET0`, `SNABB_TELNET1`—Optional telnet ports to use in tests
  that require them. The default is 5000 and 5001.

* `SNABB_PERF_SAMPLESIZE`—Optional sample size for
  `scripts/bench.sh`. The default is 1.

* `SNABB_PACKET_SIZES`, `SNABB_PACKET_SRC`, `SNABB_PACKET_DST`—Optional
  `--sizes`, `--src`, and `--dst` arguments for tests using `packetblaster
  synth`.

* `SNABB_IPERF_BENCH_CONF`, `SNABB_DPDK_BENCH_CONF`—Optional NFV configurations
  for `program/snabbnfv/selftest.sh bench` and `program/snabbnfv/dpdk_bench.sh`.


## Running a SnabbBot CI Instance

SnabbBot (`src/scripts/snabb_bot.sh`) is a shell script that acts as a
continuous integration service for Snabb repositories hosted on
GitHub. The You can run it on your own test hardware to provide unit and
performance regression testing for the upstream repository or even your
own Snabb fork.


### System Requirements

* Linux distribution (e.g. Ubuntu, RHEL, NixOS) including
 - bash
 - curl
 - awk
 - git
 - docker
 - jq
* Intel 82599 NIC and an idle CPU core on the same NUMA node (optional,
  for Intel driver and Snabb NFV tests)
* Solarflare SFN7 NIC and an idle CPU core on the same NUMA node
  (optional, for Solarflare driver tests)

SnabbBot must be run as root. It is recommended to run `snabb_bot.sh` as
a cron job like so:

```
#!/usr/bin/env bash

# SnabbBot configuration:
export GITHUB_CREDENTIALS=foo:bar

flock -x -n /var/lock/snabb_bot /path/to/snabb_bot.sh
```

### Configuration

SnabbBot is configured through the following environment variables:

* `GITHUB_CREDENTIALS`—Required. GitHub credentials of the form
  `username:password` used to post statuses.

* `REPO`—Optional. Target GitHub repository. Default is
  `snabbco/snabb` (upstream).

* `SNABBBOTDIR`—Optional. SnabbBot cache directory. Default is
  `/tmp/snabb_bot`.
