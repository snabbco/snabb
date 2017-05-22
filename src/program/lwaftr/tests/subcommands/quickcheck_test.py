"""
Test the "snabb lwaftr quickcheck" subcommand.
"""

import unittest

from test_env import SNABB_CMD, BaseTestCase


class TestQuickcheck(BaseTestCase):

    cmd_args = [
        str(SNABB_CMD), 'lwaftr', 'quickcheck', '-h'
    ]

    def test_run_nohw(self):
        output = self.run_cmd(self.cmd_args)
        self.assertIn(b'Usage: quickcheck', output,
            b'\n'.join((b'OUTPUT', output)))


if __name__ == '__main__':
    unittest.main()
