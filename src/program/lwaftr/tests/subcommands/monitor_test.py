"""
Test the "snabb lwaftr monitor" subcommand. Needs a NIC name and a TAP interface.

1. Execute "snabb lwaftr run" in on-a-stick mode and with the mirror option set.
2. Run "snabb lwaftr monitor" to set the counter and check its output.
"""

import unittest

from test_env import DATA_DIR, SNABB_CMD, BaseTestCase, nic_names, tap_name


SNABB_PCI0 = nic_names()[0]
TAP_IFACE, tap_err_msg = tap_name()


@unittest.skipUnless(SNABB_PCI0, 'NIC not configured')
@unittest.skipUnless(TAP_IFACE, tap_err_msg)
class TestMonitor(BaseTestCase):

    daemon_args = (
        str(SNABB_CMD), 'lwaftr', 'run',
        '--bench-file', '/dev/null',
        '--conf', str(DATA_DIR / 'icmp_on_fail.conf'),
        '--on-a-stick', SNABB_PCI0,
        '--mirror', TAP_IFACE,
    )
    monitor_args = (str(SNABB_CMD), 'lwaftr', 'monitor', 'all')
    wait_for_daemon_startup = True

    def test_monitor(self):
        monitor_args = list(self.monitor_args)
        monitor_args.append(str(self.daemon.pid))
        output = self.run_cmd(monitor_args)
        self.assertIn(b'Mirror address set', output,
            b'\n'.join((b'OUTPUT', output)))
        self.assertIn(b'255.255.255.255', output,
            b'\n'.join((b'OUTPUT', output)))


if __name__ == '__main__':
    unittest.main()
