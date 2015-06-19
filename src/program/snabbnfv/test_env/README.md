# test_env - Easy to use rewrite of bench_env

`test_env` is an *easy to use* rewrite of `bench_env`. It handles asset
fetching and resource management automatically and requires zero
configuration. It is used as follows (must be at the top of the
`snabbswitch` repository):

## Usage

Load `test_env`:

```
cd snabbswitch/src
source program/snabbnfv/test_env/test_env.sh
```

To start a Snabb Switch instance using `<pciaddr>`:

```
snabb <pciaddr> <args>
```

The output of the instance will be logged to `snabb<n>.log` where `<n>`
starts at 0 and increments for every new instance.

For instance to start a Snabb NFV traffic instance using `0000:86:00.0`
and the `nfv.ports` config file:

```
snabb 0000:86:00.0 "snabbnfv traffic 0000:86:00.0 nfv.ports vhost.sock"
```

To run a qemu instance to connect to a vhost user app:

```
qemu <pciaddr> <socket> <port>
```

`<pciaddr>` must be the same as the snabb instance running the vhost user
app and `<socket>` must be the vhost user socket to use. The virtual
machine will be assigned `$(mac <n>)` and `$(ip <n>)` as its MAC and IPv6
adresses and the output of qemu will be logged to `qemu<n>.log`, where
`<n>` starts at 0 and increments for every new instance. The qemu
instance will accept telnet connections on `<port>`.

## Assets

`test_env` automatically fetches and prepares all required assets and
stores them under `$HOME/.test_env/`. You can force `test_env` to refetch
the assets by deleting this directory.

## Configuration

`test_env` uses a few environment variables that can optionally
be overwritten by the caller. `test_env` will tell you when it uses a
default value so that you know which variables you did not set and what
their defaults are. The variables in question are:

* `ASSETSOURCE` - A `wget(1)` compatible URI prefix,
  `$ASSETSOURCE/{qemu.tar.gz,bzImage,qemu.img.gz}` must point to a qemu
  tarball, a kernel image and a disk image respectively.
* `MAC` - MAC address prefix for virtual machines, must include
  everything but the last segment. E.g.: `52:54:00:00:00:`
* `IP` - IPv6 address prefix for virtual machines, must include
  everything but the last segment. E.g.: `fe80::5054:ff:fe00:`
* `GUEST_MEM` - Size of qemu guest memory in megabytes.
* `QUEUES` - Number of qemu vhost-user queues, a value greater than 1
  will activate the multiqueue feature.
