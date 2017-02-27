"""
Test the "snabb lwaftr bench" subcommand. Does not need NIC cards.
"""

import os
from pathlib import Path
import unittest

from lib import sh


# Commands run under "sudo" run as root. The root's user PATH should not
# include "." (the current directory) for security reasons. If this is the
# case, when we run tests from the "src" directory (where the "snabb"
# executable is), the "snabb" executable will not be found by relative paths.
# Therefore we make all paths absolute.
TESTS_DIR = Path(os.environ['TESTS_DIR']).resolve()
DATA_DIR = TESTS_DIR / 'data'
BENCHDATA_DIR = TESTS_DIR / 'benchdata'
SNABB_CMD = TESTS_DIR.parents[2] / 'snabb'
BENCHMARK_FILENAME = 'benchtest.csv'
# Snabb creates the benchmark file in the current directory
BENCHMARK_PATH = Path.cwd() / BENCHMARK_FILENAME


class TestBenchSubcommand(unittest.TestCase):

    cmd_args = (
        SNABB_CMD, 'lwaftr', 'bench',
        '--duration', '0.1',
        '--bench-file', BENCHMARK_FILENAME,
        DATA_DIR / 'icmp_on_fail.conf',
        BENCHDATA_DIR / 'ipv4-0550.pcap',
        BENCHDATA_DIR / 'ipv6-0550.pcap',
    )

    def run_bench_test(self, cmd_args):
        output = sh.sudo(*cmd_args)
        self.assertEqual(output.exit_code, 0)
        self.assertTrue(BENCHMARK_PATH.is_file(),
            'Cannot find {}'.format(BENCHMARK_PATH))
        BENCHMARK_PATH.unlink()

    def test_standard(self):
        self.run_bench_test(self.cmd_args)

    def test_reconfigurable(self):
        reconf_cmd_args = list(self.cmd_args)
        reconf_cmd_args.insert(3, '--reconfigurable')
        self.run_bench_test(reconf_cmd_args)


if __name__ == '__main__':
    unittest.main()
