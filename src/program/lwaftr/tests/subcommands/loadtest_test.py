"""
Test the "snabb lwaftr loadtest" subcommand. Needs NIC names.

Since there are only two NIC names available in snabb-bot, and we need to
execute two programs networked to each other ("run" and "loadtest"), they
are set to on-a-stick mode, so that they use one NIC each instead of two.
"""

import unittest

from lib import sh
from lib.test_env import BENCHDATA_DIR, DATA_DIR, SNABB_CMD, nic_names


SNABB_PCI0, SNABB_PCI1 = nic_names()


@unittest.skipUnless(SNABB_PCI0 and SNABB_PCI1, 'NICs not configured')
class TestLoadtest(unittest.TestCase):

    run_cmd_args = (
        SNABB_CMD, 'lwaftr', 'run',
        '--bench-file', '/dev/null',
        '--conf', DATA_DIR / 'icmp_on_fail.conf',
        '--on-a-stick', SNABB_PCI0,
    )

    loadtest_cmd_args = (
        SNABB_CMD, 'lwaftr', 'loadtest',
        '--bench-file', '/dev/null',
        # Something quick and easy.
        '--program', 'ramp_up',
        '--step', '0.1e8',
        '--duration', '0.1',
        '--bitrate', '0.2e8',
        # Just one card for on-a-stick mode.
        BENCHDATA_DIR / 'ipv4_and_ipv6_stick_imix.pcap', 'ALL', 'ALL', SNABB_PCI1,
    )

    # Use setUpClass to only setup the "run" daemon once for all tests.
    @classmethod
    def setUpClass(cls):
        cls.run_cmd = sh.sudo(*cls.run_cmd_args, _bg=True)

    def test_loadtest(self):
        output = sh.sudo(*self.loadtest_cmd_args)
        self.assertEqual(output.exit_code, 0)
        self.assertTrue(len(output.splitlines()) > 10)

    @classmethod
    def tearDownClass(cls):
        cls.run_cmd.terminate()


if __name__ == '__main__':
    unittest.main()
