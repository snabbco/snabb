# XDP socket app (apps.xdp.xdp)

The `XDP` app implements a driver for Linux `AF_XDP` sockets.

Its links are named `input` and `output`.

    DIAGRAM: XDP
                 +-----------+
                 |           |
      input ---->*    XDP    *----> output
                 |           |
                 +-----------+

**Important:** To use the _XDP_ app, “Snabb XDP mode“ must be enabled by
calling `xdp.snabb_enable_xdp()`. Calling this function replaces Snabb's native
memory allocator with the _UMEM_ allocator. The caller must ensure that no
packets have been allocated via `packet.allocate()` prior to calling this
function.

## _Caveats_

   * Memory allocated by the UMEM allocator can not be used with _DMA_
     drivers: using the XDP app precludes the use of Snabb’s native
     hardware drivers such as `apps.intel_mp.intel_mp`.

   * Memory allocated by the UMEM allocator can not be shared with
     other Snabb processes in the same process group: using
     snabb_enable_xdp precludes the use of Interlink apps
     (`apps.interlink`).

## Maximum MTU

Due to a combination of how Snabb uses packet buffers and a limitation of
`AF_XDP` the effective maximum MTU of the XDP app is 3,582.

## Configuration

— Key **ifname**

*Required*. The name of the interface as shown in `ip link`.

— Key **filter**

*Optional*. A `pcap-filter(7)` expression. If given, packets that do not match
the filter will we passed on to the host networking stack. Must be the same for
all instances of the XDP app on a given interface!

— Key **queue**

*Optional*. Queue to bind to (zero based). The default is queue 0.

## Module functions

— Function **snabb_enable_xdp** *options*

Enables “Snabb XDP mode”. See _Caveats_!

### *Options*

*Options* is a table of configuration options. The following parameters are
supported:

 - `num_chunks`—number of UMEM chunks to allocate. The default is 200,000 which
   might not be enough depending on the number of XDP sockets used by the
   process. Each instance of the XDP app uses up to around 25,000 chunks at any
   time. However, generous over-provisioning (at least double of the expected
   residency) is recommended due to buffering in the Snabb engine.

## Setting up XDP capable devices under Linux

```
$ echo 0000:01:00.0 > /sys/bus/pci/drivers/ixgbe/bind
$ ip link set ens1f0 addr 02:00:00:00:00:00
$ ethtool --set-channels ens1f0 combined 1
```
