# test_env - Easy to use rewrite of bench_env

`test_env` is an *easy to use* rewrite of `bench_env`. It handles asset
fetching and resource management automatically and requires zero
configuration. It is used as follows (must be at the top of the
`snabbswitch` repository):


Load `test_env`:

```
source src/scripts/test_env/test_env.sh
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
app and `<socket>` must be the vhost user socket to use. The output of
qemu will be logged to `qemu<n>.log` where `<n>` starts at 0 and
increments for every new instance. The qemu instance will accept telnet
connections on `<port>`.
