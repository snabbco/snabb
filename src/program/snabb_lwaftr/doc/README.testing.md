# Testing

The alpha release of snabb-lwaftr has a minimalistic test system, which sends
the lwaftr packets and examines whether the outcoming packet(s) exactly match
what is expected.

To run these tests:

```bash
$ cd ${SNABB_LW_DIR}/tests/apps/lwaftr/end-to-end
$ sudo ./end-to-end.sh
```

This test suite includes tests for traffic class mapping, hairpinning
(including for ICMP), fragmentation, etc.
