"""
Environment support code for tests.
"""

import os
from pathlib import Path
from signal import SIGTERM
from subprocess import PIPE, Popen, TimeoutExpired, check_output
import time
import unittest


# Commands run under "sudo" run as root. The root's user PATH should not
# include "." (the current directory) for security reasons. If this is the
# case, when we run tests from the "src" directory (where the "snabb"
# executable is), the "snabb" executable will not be found by relative paths.
# Therefore we make all paths absolute.
TESTS_DIR = Path(os.environ['TESTS_DIR']).resolve()
DATA_DIR = TESTS_DIR / 'data'
COUNTERS_DIR = DATA_DIR / 'counters'
BENCHDATA_DIR = TESTS_DIR / 'benchdata'
SNABB_CMD = TESTS_DIR.parents[2] / 'snabb'
BENCHMARK_FILENAME = 'benchtest.csv'
# Snabb creates the benchmark file in the current directory
BENCHMARK_PATH = Path.cwd() / BENCHMARK_FILENAME

COMMAND_TIMEOUT = 10
ENC = 'utf-8'


def nic_names():
    return os.environ.get('SNABB_PCI0'), os.environ.get('SNABB_PCI1')


def tap_name():
    """
    Return the first TAP interface name if one found: (tap_iface, None).
    Return (None, 'No TAP interface available') if none found.
    """
    output = check_output(['ip', 'tuntap', 'list'])
    tap_iface = output.split(b':')[0]
    if not tap_iface:
        return None, 'No TAP interface available'
    return str(tap_iface, ENC), None


class BaseTestCase(unittest.TestCase):
    """
    Base class for TestCases. It has a "run_cmd" method and daemon handling,
    running a subcommand like "snabb lwaftr run" or "bench".

    Set the daemon args in "cls.daemon_args" to enable the daemon.
    Set "self.wait_for_daemon_startup" to True if it needs time to start up.
    """

    # Override these.
    daemon_args = ()
    wait_for_daemon_startup = False

    # Use setUpClass to only setup the daemon once for all tests.
    @classmethod
    def setUpClass(cls):
        if not cls.daemon_args:
            return
        cls.daemon = Popen(cls.daemon_args, stdout=PIPE, stderr=PIPE)
        if cls.wait_for_daemon_startup:
            time.sleep(1)

    def run_cmd(self, args):
        proc = Popen(args, stdout=PIPE, stderr=PIPE)
        try:
            output, errput = proc.communicate(timeout=COMMAND_TIMEOUT)
        except TimeoutExpired:
            proc.kill()
            proc.communicate()
        if proc.returncode != 0:
            msg_lines = (
                'Error running command:', str(args),
                'Exit code:', str(proc.returncode),
                'STDOUT', str(output, ENC), 'STDERR', str(errput, ENC),
            )
            self.fail('\n'.join(msg_lines))
        return output

    @classmethod
    def tearDownClass(cls):
        if not cls.daemon_args:
            return
        ret_code = cls.daemon.poll()
        if ret_code is None:
            cls.daemon.terminate()
            ret_code = cls.daemon.wait()
        if ret_code not in (0, -SIGTERM):
            print('Error terminating daemon:', cls.daemon.args)
            print('Exit code:', ret_code)
            print('STDOUT\n', str(cls.daemon.stdout.read(), ENC))
            print('STDERR\n', str(cls.daemon.stderr.read(), ENC))
        cls.daemon.stdout.close()
        cls.daemon.stderr.close()
