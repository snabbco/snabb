"""
Test the "snabb lwaftr run" subcommand. Needs NIC names.
"""

import unittest

from lib import sh
from lib.test_env import DATA_DIR, SNABB_CMD, nic_names


SNABB_PCI0, SNABB_PCI1 = nic_names()


@unittest.skipUnless(SNABB_PCI0 and SNABB_PCI1, 'NICs not configured')
class TestRun(unittest.TestCase):

    cmd_args = (
        SNABB_CMD, 'lwaftr', 'run',
        '--duration', '0.1',
        '--bench-file', '/dev/null',
        '--conf', DATA_DIR / 'icmp_on_fail.conf',
        '--v4', SNABB_PCI0,
        '--v6', SNABB_PCI1,
    )

    def execute_run_test(self, cmd_args):
        output = sh.sudo(*cmd_args)
        self.assertEqual(output.exit_code, 0)
        self.assertTrue(len(output.splitlines()) > 1)

    def test_run_standard(self):
        self.execute_run_test(self.cmd_args)

    def test_run_reconfigurable(self):
        reconf_cmd_args = list(self.cmd_args)
        reconf_cmd_args.insert(3, '--reconfigurable')
        self.execute_run_test(reconf_cmd_args)


if __name__ == '__main__':
    unittest.main()
