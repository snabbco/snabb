"""
Test the "snabb lwaftr quickcheck" subcommand.
"""

import unittest

from test_env import ENC, SNABB_CMD, BaseTestCase


class TestQuickcheck(BaseTestCase):

    cmd_args = (str(SNABB_CMD), 'lwaftr', 'quickcheck', '-h')

    def test_quickcheck(self):
        output = str(self.run_cmd(self.cmd_args), ENC)
        self.assertIn('Usage: quickcheck', output,
            '\n'.join(('OUTPUT', output)))


if __name__ == '__main__':
    unittest.main()
