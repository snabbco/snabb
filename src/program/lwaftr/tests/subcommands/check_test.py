"""
Test the "snabb lwaftr check" subcommand. Does not need NIC names.
"""

import unittest

from lib import sh
from lib.test_env import COUNTERS_DIR, DATA_DIR, SNABB_CMD


class TestCheck(unittest.TestCase):

    cmd_args = (
        SNABB_CMD, 'lwaftr', 'check',
        DATA_DIR / 'icmp_on_fail.conf',
        DATA_DIR / 'empty.pcap', DATA_DIR / 'empty.pcap',
        '/dev/null', '/dev/null',
        COUNTERS_DIR / 'empty.lua',
    )

    def execute_check_test(self, cmd_args):
        output = sh.sudo(*cmd_args)
        self.assertEqual(output.exit_code, 0)

    def test_check_standard(self):
        self.execute_check_test(self.cmd_args)

    def test_check_on_a_stick(self):
        onastick_cmd_args = list(self.cmd_args)
        onastick_cmd_args.insert(3, '--on-a-stick')
        self.execute_check_test(onastick_cmd_args)


if __name__ == '__main__':
    unittest.main()
