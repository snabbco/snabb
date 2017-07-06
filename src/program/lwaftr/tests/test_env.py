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

    @classmethod
    def get_config_path(cls, path):
        """  Gets the config path.

        This will either produce a new configuration specifically for the test
        so if specific PCI cards should be used. It otherwise returns the config
        path passed in."""
        ipv4_nic, ipv6_nic = nic_names()
        if ipv4_nic is None and ipv6_nic is None :
            return path

        if ipv6_nic is not None:
            raise Exception("Missing IPv4 internal NIC information.")

        # Figure out this config's path
        filename = "/".join((jit_config_dir(), path.split("/")[-1]))

        if os.path.isfile(filename):
            return filename

        internal_device = "internal[device={device}]".format(
            device=ipv4_nic
        )
        external_device = "external[device={device}]".format(
            device=ipv6_nic
        )
        cmd = [
            str(SNABB_CMD), "lwaftr", "migrate-configuration", "-f",
            "pci-device", "-o", "from[device=test]", "-o", internal_device
        ]

        if ipv6_nic:
            cmd.extend(("-o", external_device))
        cmd.append(path)

        # Migrate the config to our new one with the PCI device.
        proc = Popen(cmd, stdout=PIPE)
        proc.wait()

        # Finally write the config out.
        fout = open(filename, "w")
        fout.write(proc.stdout.read().decode("utf-8"))
        fout.close()

        return filename

    def run_cmd(self, args):
        proc = Popen(args, stdout=PIPE, stderr=PIPE)
        try:
            output, errput = proc.communicate(timeout=COMMAND_TIMEOUT)
        except TimeoutExpired:
            proc.stdout.close()
            proc.stderr.close()
            print('\nTimeout running command, trying to kill PID %s' % proc.pid)
            proc.kill()
            raise
        if proc.returncode != 0:
            msg_lines = (
                'Error running command:', " ".join(args),
                'Daemon Command:', " ".join(self.daemon_args),
                'Exit code: %s' % proc.returncode,
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
        if ret_code in (0, -SIGTERM):
            cls.daemon.stdout.close()
            cls.daemon.stderr.close()
        else:
            cls.reportAndFail('Error terminating daemon:', ret_code)
