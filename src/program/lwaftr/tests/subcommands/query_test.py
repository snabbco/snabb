"""
Test the "snabb lwaftr query" subcommand. Needs NIC names.
"""

import os
from pathlib import Path
import unittest

from test_env import DATA_DIR, ENC, SNABB_CMD, BaseTestCase, nic_names


DAEMON_PROC_NAME = 'query_test_daemon'
SNABB_PCI0, SNABB_PCI1 = nic_names()
RUN_DIR = Path('/var/run/snabb')


@unittest.skipUnless(SNABB_PCI0 and SNABB_PCI1, 'NICs not configured')
class TestQueryStandard(BaseTestCase):

    daemon_args = (
        str(SNABB_CMD), 'lwaftr', 'run',
        '--name', DAEMON_PROC_NAME,
        '--conf', str(DATA_DIR / 'no_icmp.conf'),
        '--v4', SNABB_PCI0,
        '--v6', SNABB_PCI1,
    )

    query_args = (str(SNABB_CMD), 'lwaftr', 'query')

    def test_query_all(self):
        all_args = list(self.query_args)
        all_args.append('--list-all')
        output = self.run_cmd(all_args)
        self.assertGreater(
            len(output.splitlines()), 1,
            '\n'.join(('OUTPUT', str(output, ENC))))

    def execute_query_test(self, cmd_args):
        output = self.run_cmd(cmd_args)
        self.assertGreater(
            len(output.splitlines()), 1,
            '\n'.join(('OUTPUT', str(output, ENC))))
        cmd_args.append('memuse-ipv')
        output = self.run_cmd(cmd_args)
        self.assertGreater(
            len(output.splitlines()), 1,
            '\n'.join(('OUTPUT', str(output, ENC))))
        cmd_args[-1] = "no-such-counter"
        output = self.run_cmd(cmd_args)
        self.assertEqual(
            len(output.splitlines()), 1,
            '\n'.join(('OUTPUT', str(output, ENC))))

    def get_lwaftr_pid(self):
        output = str(self.run_cmd(('ps', 'aux')), ENC)
        pids = []
        for line in output.splitlines():
            if SNABB_PCI0 in line:
                pids.append(line.split()[1])
        for pid in pids:
            if (RUN_DIR / pid / 'apps' / 'lwaftr').is_dir():
                return pid

    def test_query_by_pid(self):
        lwaftr_pid = self.get_lwaftr_pid()
        pid_args = list(self.query_args)
        pid_args.append(str(lwaftr_pid))
        self.execute_query_test(pid_args)

    def test_query_by_name(self):
        name_args = list(self.query_args)
        name_args.extend(('--name', DAEMON_PROC_NAME))
        self.execute_query_test(name_args)


@unittest.skipUnless(SNABB_PCI0 and SNABB_PCI1, 'NICs not configured')
class TestQueryReconfigurable(TestQueryStandard):

    daemon_args = (
        str(SNABB_CMD), 'lwaftr', 'run', '--reconfigurable',
        '--name', DAEMON_PROC_NAME,
        '--conf', str(DATA_DIR / 'no_icmp.conf'),
        '--v4', SNABB_PCI0,
        '--v6', SNABB_PCI1,
    )

    def get_all_leader_pids(self):
        output = str(self.run_cmd(('ps', 'aux')), ENC)
        pids = []
        for line in output.splitlines():
            if ((SNABB_PCI0 in line) and
                    ('--reconfigurable' in line) and
                    ('grep' not in line)):
                pids.append(line.split()[1])
        return pids

    def get_leader_pid(self):
        for pid in self.get_all_leader_pids():
            if (RUN_DIR / pid).is_dir():
                return pid

    def get_follower_pid(self):
        leader_pids = self.get_all_leader_pids()
        for run_pid in RUN_DIR.iterdir():
            run_pid = run_pid.name
            for leader_pid in leader_pids:
                group_link = RUN_DIR / run_pid / 'group'
                if group_link.is_symlink():
                    target = Path(os.readlink(str(group_link)))
                    # ('/', 'var', 'run', 'snabb', pid, 'group')
                    target_pid = target.parts[4]
                    if target_pid == leader_pid:
                        return run_pid

    def test_query_by_pid(self):
        leader_pid = self.get_leader_pid()
        if not leader_pid:
            self.fail('Could not find the leader PID')
        pid_args = list(self.query_args)
        pid_args.append(str(leader_pid))
        self.execute_query_test(pid_args)
        follower_pid = self.get_follower_pid()
        if not follower_pid:
            self.fail('Could not find the follower PID')
        pid_args = list(self.query_args)
        pid_args.append(str(follower_pid))
        self.execute_query_test(pid_args)


if __name__ == '__main__':
    unittest.main()
