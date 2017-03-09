"""
Test the "snabb lwaftr loadtest" subcommand. Needs NIC names.

Since there are only two NIC names available in snabb-bot, and we need to
execute two programs networked to each other ("run" and "loadtest"), they
are set to on-a-stick mode, so that they use one NIC each instead of two.
"""

import unittest

from lib.test_env import (
    BENCHDATA_DIR, DATA_DIR, SNABB_CMD, BaseTestCase, nic_names)


SNABB_PCI0, SNABB_PCI1 = nic_names()


@unittest.skipUnless(SNABB_PCI0 and SNABB_PCI1, 'NICs not configured')
class TestLoadtest(BaseTestCase):

    daemon_args = (
        str(SNABB_CMD), 'lwaftr', 'run',
        '--bench-file', '/dev/null',
        '--conf', str(DATA_DIR / 'icmp_on_fail.conf'),
        '--on-a-stick', SNABB_PCI0,
    )
    loadtest_args = (
        str(SNABB_CMD), 'lwaftr', 'loadtest',
        '--bench-file', '/dev/null',
        # Something quick and easy.
        '--program', 'ramp_up',
        '--step', '0.1e8',
        '--duration', '0.1',
        '--bitrate', '0.2e8',
        # Just one card for on-a-stick mode.
        str(BENCHDATA_DIR / 'ipv4_and_ipv6_stick_imix.pcap'), 'ALL', 'ALL',
        SNABB_PCI1,
    )
    wait_for_daemon_startup = True

    def test_loadtest(self):
        output = self.run_cmd(self.loadtest_args)
        self.assertGreater(len(output.splitlines()), 10,
            b'\n'.join((b'OUTPUT', output)))


if __name__ == '__main__':
    unittest.main()
