"""
Test the "snabb lwaftr run" subcommand. Needs NIC names.
"""

import unittest

from test_env import DATA_DIR, SNABB_CMD, BaseTestCase, nic_names


SNABB_PCI0, SNABB_PCI1 = nic_names()

@unittest.skipUnless(SNABB_PCI0 and SNABB_PCI1, 'NICs not configured')
class TestRun(BaseTestCase):

    cmd_args = (
        str(SNABB_CMD), 'lwaftr', 'run',
        '--duration', '1',
        '--bench-file', '/dev/null',
        '--conf', str(DATA_DIR / 'icmp_on_fail.conf'),
        '--v4', SNABB_PCI0,
        '--v6', SNABB_PCI1
    )

    def test_run(self):
        output = self.run_cmd(self.cmd_args)
        self.assertIn(b'link report', output,
            b'\n'.join((b'OUTPUT', output)))

if __name__ == '__main__':
    unittest.main()
