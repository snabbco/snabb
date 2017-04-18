"""
Test the "snabb lwaftr check" subcommand. Does not need NIC names.
"""

import unittest

from test_env import COUNTERS_DIR, DATA_DIR, SNABB_CMD, BaseTestCase


class TestCheck(BaseTestCase):

    cmd_args = (
        str(SNABB_CMD), 'lwaftr', 'check',
        str(DATA_DIR / 'icmp_on_fail.conf'),
        str(DATA_DIR / 'empty.pcap'), str(DATA_DIR / 'empty.pcap'),
        '/dev/null', '/dev/null',
        str(COUNTERS_DIR / 'empty.lua'),
    )

    def execute_check_test(self, cmd_args):
        self.run_cmd(cmd_args)
        # run_cmd checks the exit code and fails the test if it is not zero.

    def test_check_standard(self):
        self.execute_check_test(self.cmd_args)

    def test_check_on_a_stick(self):
        onastick_args = list(self.cmd_args)
        onastick_args.insert(3, '--on-a-stick')
        self.execute_check_test(onastick_args)


if __name__ == '__main__':
    unittest.main()
