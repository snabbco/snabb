## Snabbnfv-traffic Selftest

The `selftest.sh` script uses `bench_env` to provide quite extensive
integration test suite for `src/designs/snabbnfv-traffic`. It boots two
virtual machines (guests) connected by a `snabbnfv-traffic` instance and
runs shell commands on these guests to assert properties of a given `nfv
configuration`.

For more details see [Testing NFV Functionality](https://github.com/eugeneia/snabbswitch/wiki/Testing-NFV-functionality).

### How To: Run this test suite

#### Prerequistes

* An account on `chur`, see [Snabb Lab](https://github.com/SnabbCo/snabbswitch/wiki/Snabb-Lab)
* A copy of the `snabbswitch` repository

#### Step-by-Step Setup (on `chur`)

Step 1: Copy `/opt/test` to your home directory:

```
$ cp -r /opt/test ~/
```

Step 2: Softlink `~/test/bench_conf.sh` to `~/bench_conf.sh`.

```
$ ln -s ~/test/bench_conf.sh ~/bench_conf.sh
```

Step 3: Edit `~/test/bench_conf.sh` and replace `<pciaddr>` with the PCI
address of the Intel 10-G NIC you want to use (e.g. `0000:88:00.0`). Note:
You should also adjust `TELNET_PORT0` and `TELNET_PORT1` to avoid port
clashes with other `bench_env` users on the system.

Your done. Run the test suite from the `snabbswitch/src` directory like
so (assuming your `snabbswitch` repository is located at
`~/snabbswitch/`):

```
$ cd ~/snabbswitch/src
$ sudo program/snabbnfv/selftest.sh
[...]
```

#### Customizing Your Setup

Consult `src/scripts/bench_env/README` on how to create custom guest
images. In order for `src/program/snabbnfv/selftest.sh` to run the
following packages must be present on the guest: `ethtool`, `iperf`,
`tcpdump` and `netcat`.
