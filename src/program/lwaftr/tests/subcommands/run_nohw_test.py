"""
Test the "snabb lwaftr run-nohw" subcommand.
"""

import unittest

from random import randint
from subprocess import check_call
from test_env import DATA_DIR, SNABB_CMD, BaseTestCase


class TestRunNoHW(BaseTestCase):

    cmd_args = [
        str(SNABB_CMD), 'lwaftr', 'run-nohw',
    ]
    cmd_options = {
        '--duration': '1',
        '--bench-file': '/dev/null',
        '--conf': str(DATA_DIR / 'icmp_on_fail.conf'),
        '--inet-if': '',
        '--b4-if': '',
    }
    veths = []

    @classmethod
    def setUpClass(cls):
        veth0 = cls.random_veth_name()
        veth1 = cls.random_veth_name()
        # Create veth pair.
        check_call(
            ('ip', 'link', 'add', veth0, 'type', 'veth', 'peer', 'name', veth1)
        )
        # Set interfaces up.
        check_call(('ip', 'link', 'set', veth0, 'up'))
        check_call(('ip', 'link', 'set', veth1, 'up'))
        # Add interface names to class.
        cls.veths.append(veth0)
        cls.veths.append(veth1)

    @classmethod
    def random_veth_name(cls):
        return 'veth%s' % randint(10000, 999999)

    def test_run_nohw(self):
        self.cmd_options['--inet-if'] = self.veths[0]
        self.cmd_options['--b4-if'] = self.veths[1]
        output = self.run_cmd(self.build_cmd())
        self.assertIn(b'link report', output,
            b'\n'.join((b'OUTPUT', output)))

    def build_cmd(self):
        result = self.cmd_args
        for key, value in self.cmd_options.items():
            result.extend((key, value))
        return result

    @classmethod
    def tearDownClass(cls):
        check_call(('ip', 'link', 'delete', cls.veths[0]))


if __name__ == '__main__':
    unittest.main()
