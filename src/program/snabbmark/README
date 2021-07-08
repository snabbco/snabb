Usage:
  snabbmark basic1    <npackets>
    Benchmark basic app network packet flow.

  snabbmark nfvconfig  <config-file-x> <config-file-y> <n>
    Benchmark loading <config-file-x> and transitioning from <config-file-x>
    to <config-file-y> <n> times.

    Uses SNABB_PCI0.

  snabbmark solarflare <npackets> <packet-size> [<timeout>]
    Send the given number of packets through a Solarflare NIC.  The test
    assumes that the first two Solarflare NICs are connected
    back-to-back.

    The optional <timeout> parameter can be used to specify a timeout in
    seconds. If supplied the benchmark run for no longer than <timeout>
    seconds.

    Uses SNABB_PCI_SOLARFLARE0 or SNABB_PCI0 and SNABB_PCI_SOLARFLARE1 or
    SNABB_PCI1.

    Example usage with 10 million packets, packet size 128 bytes:
    solarflare 10e6 128

  snabbmark intel1g <npackets> <packet-size> [<timeout>]
    Send the given number of packets through a Intel i210/i350 NIC. The test
    assumes that the two Intel NICs are connected
    back-to-back.

    The optional <timeout> parameter can be used to specify a timeout in
    seconds. If supplied the benchmark run for no longer than <timeout>
    seconds.

    Uses SNABB_PCI0 and SNABB_PCI1.

    Example usage with 10 million packets, packet size 128 bytes:
    sudo SNABB_PCI0="0000:02:00.0"  SNABB_PCI1="0000:03:00.0" ./snabb snabbmark intel1g 10e6 128

  snabbmark esp <npackets> <packet-size> [<mode>] [<direction>] [<aead>]
    Benchmark ESP encapsulating or decapsulatiing <npackets> of
    <packet-size>. <mode> can be either "transport" (default) or "tunnel",
    <direction> can be either "encapsulate" or "decapsulate" (default).
    <aead> defaults to aes-gcm-16-icv.

    Optionally, a LuaJIT profiler option string can be supplied as <profile>,
    which will cause the benchmark run to be profiled accordingly.

    Note: transport mode may generally score better because it has to
    encapsulate 40 bytes less per packet because of the enclosed IPv6 header
    in tunnel mode, and this micro-benchmark measures end-to-end throughput.

  snabbmark hash [<key-size>]
    Benchmark hash functions used for internal data structures.

  snabbmark ctable
    Benchmark insertion and lookup for the "ctable" data structure.

  snabbmark checksum
    Benchmark checksum computation implementations in C and DynASM.
