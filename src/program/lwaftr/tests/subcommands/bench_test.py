"""
Test the "snabb lwaftr bench" subcommand. Does not need NIC cards.
"""

import unittest

from lib.test_env import (BENCHMARK_FILENAME, BENCHMARK_PATH, DATA_DIR,
    BENCHDATA_DIR, SNABB_CMD, BaseTestCase)


class TestBench(BaseTestCase):

    cmd_args = (
        str(SNABB_CMD), 'lwaftr', 'bench',
        '--duration', '0.1',
        '--bench-file', BENCHMARK_FILENAME,
        str(DATA_DIR / 'icmp_on_fail.conf'),
        str(BENCHDATA_DIR / 'ipv4-0550.pcap'),
        str(BENCHDATA_DIR / 'ipv6-0550.pcap'),
    )

    def execute_bench_test(self, cmd_args):
        self.run_cmd(cmd_args)
        self.assertTrue(BENCHMARK_PATH.is_file(),
            'Cannot find {}'.format(BENCHMARK_PATH))
        BENCHMARK_PATH.unlink()

    def test_bench_standard(self):
        self.execute_bench_test(self.cmd_args)

    def test_bench_reconfigurable(self):
        reconf_args = list(self.cmd_args)
        reconf_args.insert(3, '--reconfigurable')
        self.execute_bench_test(reconf_args)


if __name__ == '__main__':
    unittest.main()
