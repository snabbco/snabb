"""
Test the "snabb lwaftr run_nohw" subcommand.
"""

import unittest

from random import randint
from subprocess import call, check_call
from test_env import DATA_DIR, SNABB_CMD, BaseTestCase

class TestRun(BaseTestCase):

    program = [
        str(SNABB_CMD), 'lwaftr', 'run_nohw',
    ]
    cmd_args = {
        '--duration': '1',
        '--bench-file': '/dev/null',
        '--conf': str(DATA_DIR / 'icmp_on_fail.conf'),
        '--inet-if': '',
        '--b4-if': '',
    }
    veths = []

    @classmethod
    def setUpClass(cls):
        cls.create_veth_pair()

    @classmethod
    def create_veth_pair(cls):
        veth0 = cls.random_veth_name()
        veth1 = cls.random_veth_name()

        # Create veth pair.
        check_call(('ip', 'link', 'add', veth0, 'type', 'veth', 'peer', \
            'name', veth1))

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
        self.execute_run_test(self.cmd_args)

    def execute_run_test(self, cmd_args):
        self.cmd_args['--inet-if'] = self.veths[0]
        self.cmd_args['--b4-if'] = self.veths[1]
        output = self.run_cmd(self.build_cmd())
        self.assertIn(b'link report', output,
            b'\n'.join((b'OUTPUT', output)))

    def build_cmd(self):
        result = self.program
        for item in self.cmd_args.items():
            for each in item:
                result.append(each)
        return result

    @classmethod
    def tearDownClass(cls):
        cls.remove_veths()

    @classmethod
    def remove_veths(cls):
        for i in range(0, len(cls.veths), 2):
            check_call(('ip', 'link', 'delete', cls.veths[i]))

if __name__ == '__main__':
    unittest.main()
