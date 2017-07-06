"""
Test the "snabb lwaftr monitor" subcommand. Needs a NIC name and a TAP interface.

1. Execute "snabb lwaftr run" in on-a-stick mode and with the mirror option set.
2. Run "snabb lwaftr monitor" to set the counter and check its output.
"""

from random import randint
from subprocess import call, check_call
import unittest

from test_env import DATA_DIR, SNABB_CMD, BaseTestCase, nic_names


DAEMON_PROC_NAME = 'monitor-test-daemon'
SNABB_PCI0 = nic_names()[0]


@unittest.skipUnless(SNABB_PCI0, 'NIC not configured')
class TestMonitor(BaseTestCase):

    daemon_args = [
        str(SNABB_CMD), 'lwaftr', 'run',
        '--name', DAEMON_PROC_NAME,
        '--bench-file', '/dev/null',
        '--conf', str(DATA_DIR / 'icmp_on_fail.conf'),
        '--on-a-stick', SNABB_PCI0,
        '--mirror',  # TAP interface name added in setUpClass.
    ]
    monitor_args = (
        str(SNABB_CMD), 'lwaftr', 'monitor', '--name', DAEMON_PROC_NAME, 'all')

    # Use setUpClass to only setup the daemon once for all tests.
    @classmethod
    def setUpClass(cls):
        # Create the TAP interface and append its name to daemon_args
        # before calling the superclass' setUpClass, which needs both.
        # 'tapXXXXXX' where X is a 0-9 digit.
        cls.tap_name = 'tap%s' % randint(100000, 999999)
        check_call(('ip', 'tuntap', 'add', cls.tap_name, 'mode', 'tap'))
        cls.daemon_args.append(cls.tap_name)
        try:
            super(TestMonitor, cls).setUpClass()
        except Exception:
            # Clean up the TAP interface.
            call(('ip', 'tuntap', 'delete', cls.tap_name, 'mode', 'tap'))
            raise

    def test_monitor(self):
        output = self.run_cmd(self.monitor_args)
        self.assertIn(b'Mirror address set', output,
            b'\n'.join((b'OUTPUT', output)))
        self.assertIn(b'255.255.255.255', output,
            b'\n'.join((b'OUTPUT', output)))

    @classmethod
    def tearDownClass(cls):
        try:
            super(TestMonitor, cls).tearDownClass()
        finally:
            # Clean up the TAP interface.
            call(('ip', 'tuntap', 'delete', cls.tap_name, 'mode', 'tap'))


if __name__ == '__main__':
    unittest.main()
