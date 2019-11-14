"""
Environment support code for tests.
"""

from pathlib import Path
from signal import SIGTERM
from subprocess import PIPE, Popen, TimeoutExpired
import os
import time
import unittest
import random
import string


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
DAEMON_STARTUP_WAIT = 1
ENC = 'utf-8'


def nic_names():
    return os.environ.get('SNABB_PCI0'), os.environ.get('SNABB_PCI1')

def jit_config_dir():
    return os.environ.get("JIT_CONFIG_DIR")

class BaseTestCase(unittest.TestCase):
    """
    Base class for TestCases. It has a "run_cmd" method and daemon handling,
    running a subcommand like "snabb lwaftr run" or "bench".

    Set "daemon_args" to enable the daemon.
    """

    # Override these.
    daemon_args = ()

    # Use setUpClass to only setup the daemon once for all tests.
    @classmethod
    def setUpClass(cls):
        if not cls.daemon_args:
            return
        cls.daemon = Popen(cls.daemon_args, stdout=PIPE, stderr=PIPE)
        time.sleep(DAEMON_STARTUP_WAIT)
        # Check that the daemon started up correctly.
        ret_code = cls.daemon.poll()
        if ret_code is not None:
            cls.reportAndFail('Error starting up daemon:', ret_code)

    @classmethod
    def reportAndFail(cls, msg, ret_code):
            msg_lines = [
                msg, str(cls.daemon.args),
                'Exit code: %s' % ret_code,
            ]
            if cls.daemon.stdout.readable:
                msg_lines.extend(
                    ('STDOUT\n', str(cls.daemon.stdout.read(), ENC)))
            if cls.daemon.stderr.readable:
                msg_lines.extend(
                    ('STDERR\n', str(cls.daemon.stderr.read(), ENC)))
            cls.daemon.stdout.close()
            cls.daemon.stderr.close()
            cls.fail(cls, '\n'.join(msg_lines))

    def run_cmd(self, args, ret=0):
        proc = Popen(args, stdout=PIPE, stderr=PIPE)
        try:
            output, errput = proc.communicate(timeout=COMMAND_TIMEOUT)
        except TimeoutExpired:
            proc.stdout.close()
            proc.stderr.close()
            print('\nTimeout running command, trying to kill PID %s' % proc.pid)
            proc.kill()
            raise
        if proc.returncode != ret:
            msg_lines = (
                'Error running command:', " ".join(args),
                'Daemon Command:', " ".join(self.daemon_args),
                'Exit code: %s' % proc.returncode,
                'STDOUT', str(output, ENC), 'STDERR', str(errput, ENC),
            )
            self.fail('\n'.join(msg_lines))
        return output

    @staticmethod
    def stop_daemon(daemon):
        ret_code = daemon.poll()
        if ret_code is None:
            daemon.terminate()
            ret_code = daemon.wait()
        if ret_code in (0, -SIGTERM):
            daemon.stdout.close()
            daemon.stderr.close()
        else:
            raise Exception('Error terminating deamon: ' + str(ret_code))

    @classmethod
    def tearDownClass(cls):
        if not cls.daemon_args:
            return
        cls.stop_daemon(cls.daemon)
