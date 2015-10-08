# Testing Snabb Switch

Some Snabb Switch tests require configuration through environment
variables. Described below are the environment variables used throughout
the tests:

* `SNABB_PCI0`, `SNABB_PCI1`—PCI addresses of two wired NICs. These are
  the only variables required to run most of the test suite.

* `SNABB_PCI_INTEL0`, `SNABB_PCI_INTEL1`—Optional PCI addresses of two
  wired Intel NICs. These are preferred over `SNABB_PCI0` and
  `SNABB_PCI1` in Intel specific tests.

* `SNABB_PCI_SOLARFLARE0`, `SNABB_PCI_SOLARFLARE1`—Optional PCI addresses
  of two wired Solarflare NICs. These are preferred over `SNABB_PCI0` and
  `SNABB_PCI1` in Solarflare specific tests.

* `SNABB_TELNET0`, `SNABB_TELNET1`—Optional telnet ports to use in tests
  that require them. The default is 5000 and 5001.

* `SNABB_PCAP`—Optional PCAP file for use in tests that require one. The
  default depends on the individual test.

* `SNABB_PERF_SAMPLESIZE`—Optional sample size for
  `scripts/bench.sh`. The default is 1.
