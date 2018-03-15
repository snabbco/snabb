"""
Test the "snabb lwaftr run" subcommand. Needs NIC names.
"""

import unittest

from test_env import DATA_DIR, SNABB_CMD, BaseTestCase, nic_names, ENC


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
        output = self.run_cmd(self.cmd_args).decode(ENC)
        self.assertIn("Migrating instance", output)

    def test_run_on_a_stick_migration(self):
        # The LwAFTR should be abel to migrate from non-on-a-stick -> on-a-stick
        run_cmd = list(self.cmd_args)[:-4]
        run_cmd.extend((
            "--on-a-stick",
            SNABB_PCI0
        ))

        # The best way to check is to see if it's what it's saying it'll do.
        output = self.run_cmd(run_cmd).decode(ENC)
        self.assertIn("Migrating instance", output)

        migration_line = [l for l in output.split("\n") if "Migrating" in l][0]
        self.assertIn(SNABB_PCI0, migration_line)

if __name__ == '__main__':
    unittest.main()
