"""
Test the "snabb lwaftr config" subcommand. Does not need NIC names because
it uses the "bench" subcommand.
"""

import json
import os
from signal import SIGTERM
import socket
from subprocess import PIPE, Popen
import time
import unittest

from test_env import BENCHDATA_DIR, DATA_DIR, ENC, SNABB_CMD, BaseTestCase


DAEMON_PROC_NAME = 'config_test_daemon'
DAEMON_ARGS = (
    str(SNABB_CMD), 'lwaftr', 'bench', '--reconfigurable',
    '--bench-file', '/dev/null',
    '--name', DAEMON_PROC_NAME,
    str(DATA_DIR / 'icmp_on_fail.conf'),
    str(BENCHDATA_DIR / 'ipv4-0550.pcap'),
    str(BENCHDATA_DIR / 'ipv6-0550.pcap'),
)
SOCKET_PATH = '/tmp/snabb-lwaftr-listen-sock-%s' % DAEMON_PROC_NAME


class TestConfigGet(BaseTestCase):
    """
    Test querying from a known config, testing basic "getting".
    It performs numerous gets on different paths.
    """

    daemon_args = DAEMON_ARGS
    config_args = (str(SNABB_CMD), 'config', 'get', DAEMON_PROC_NAME)

    def test_get_internal_iface(self):
        cmd_args = list(self.config_args)
        cmd_args.append('/softwire-config/internal-interface/ip')
        output = self.run_cmd(cmd_args)
        self.assertEqual(
            output.strip(), b'8:9:a:b:c:d:e:f',
            '\n'.join(('OUTPUT', str(output, ENC))))

    def test_get_external_iface(self):
        cmd_args = list(self.config_args)
        cmd_args.append('/softwire-config/external-interface/ip')
        output = self.run_cmd(cmd_args)
        self.assertEqual(
            output.strip(), b'10.10.10.10',
            '\n'.join(('OUTPUT', str(output, ENC))))

    def test_get_b4_ipv6(self):
        cmd_args = list(self.config_args)
        # Implicit string concatenation, do not add commas.
        cmd_args.append(
            '/softwire-config/binding-table/softwire'
            '[ipv4=178.79.150.233][psid=7850]/b4-ipv6')
        output = self.run_cmd(cmd_args)
        self.assertEqual(
            output.strip(), b'127:11:12:13:14:15:16:128',
            '\n'.join(('OUTPUT', str(output, ENC))))

    def test_get_ietf_path(self):
        cmd_args = list(self.config_args)[:-1]
        cmd_args.extend((
            '--schema=ietf-softwire', DAEMON_PROC_NAME,
            # Implicit string concatenation, do not add commas.
            '/softwire-config/binding/br/br-instances/'
            'br-instance[id=1]/binding-table/binding-entry'
            '[binding-ipv6info=127:22:33:44:55:66:77:128]/binding-ipv4-addr',
        ))
        output = self.run_cmd(cmd_args)
        self.assertEqual(
            output.strip(), b'178.79.150.15',
            '\n'.join(('OUTPUT', str(output, ENC))))


class TestConfigListen(BaseTestCase):
    """
    Test it can listen, send a command and get a response. Only test the
    socket method of communicating with the listen command, due to the
    difficulties of testing interactive scripts.
    """

    daemon_args = DAEMON_ARGS
    listen_args = (str(SNABB_CMD), 'config', 'listen',
        '--socket', SOCKET_PATH, DAEMON_PROC_NAME)

    def test_listen(self):
        # Start the listen command with a socket.
        listen_daemon = Popen(self.listen_args, stdout=PIPE, stderr=PIPE)
        # Wait a short while for the socket to be created.
        time.sleep(1)
        # Send command to and receive response from the listen command.
        # (Implicit string concatenation, no summing needed.)
        get_cmd = (b'{ "id": "0", "verb": "get",'
            b' "path": "/routes/route[addr=1.2.3.4]/port" }\n')
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            sock.connect(SOCKET_PATH)
            sock.sendall(get_cmd)
            resp = str(sock.recv(200), ENC)
        finally:
            sock.close()
        status = json.loads(resp)['status']
        self.assertEqual(status, 'ok')
        # Terminate the listen command.
        listen_daemon.terminate()
        ret_code = listen_daemon.wait()
        if ret_code not in (0, -SIGTERM):
            print('Error terminating daemon:', listen_daemon.args)
            print('Exit code:', ret_code)
            print('STDOUT\n', str(listen_daemon.stdout.read(), ENC))
            print('STDERR\n', str(listen_daemon.stderr.read(), ENC))
        listen_daemon.stdout.close()
        listen_daemon.stderr.close()
        os.unlink(SOCKET_PATH)


class TestConfigMisc(BaseTestCase):

    daemon_args = DAEMON_ARGS

    def get_cmd_args(self, action):
        cmd_args = list((str(SNABB_CMD), 'config', 'XXX', DAEMON_PROC_NAME))
        cmd_args[2] = action
        return cmd_args

    def test_add(self):
        """
        Add a softwire section, get it back and check all the values.
        """
        # External IPv4.
        add_args = self.get_cmd_args('add')
        add_args.extend((
            '/softwire-config/binding-table/softwire',
            '{ ipv4 1.2.3.4; psid 72; b4-ipv6 ::1; br 1; }',
        ))
        self.run_cmd(add_args)
        get_args = self.get_cmd_args('get')
        get_args.append(
            '/softwire-config/binding-table/softwire[ipv4=1.2.3.4][psid=72]')
        output = self.run_cmd(get_args)
        # run_cmd checks the exit code and fails the test if it is not zero.
        get_args[-1] += '/b4-ipv6'
        self.assertEqual(
            output.strip(), b'b4-ipv6 ::1;',
            '\n'.join(('OUTPUT', str(output, ENC))))

    def test_get_state(self):
        get_state_args = self.get_cmd_args('get-state')
        # Select a few at random which should have non-zero results.
        for query in (
                '/softwire-state/in-ipv4-bytes',
                '/softwire-state/out-ipv4-bytes',
            ):
            cmd_args = list(get_state_args)
            cmd_args.append(query)
            output = self.run_cmd(cmd_args)
            self.assertNotEqual(
                output.strip(), b'0',
                '\n'.join(('OUTPUT', str(output, ENC))))
        get_state_args.append('/')
        self.run_cmd(get_state_args)
        # run_cmd checks the exit code and fails the test if it is not zero.

    def test_remove(self):
        # Verify that the thing we want to remove actually exists.
        get_args = self.get_cmd_args('get')
        get_args.append(
            # Implicit string concatenation, no summing needed.
            '/softwire-config/binding-table/softwire'
            '[ipv4=178.79.150.2][psid=7850]/'
        )
        self.run_cmd(get_args)
        # run_cmd checks the exit code and fails the test if it is not zero.
        # Remove it.
        remove_args = list(get_args)
        remove_args[2] = 'remove'
        self.run_cmd(get_args)
        # run_cmd checks the exit code and fails the test if it is not zero.
        # Verify we cannot find it anymore.
        self.run_cmd(get_args)
        # run_cmd checks the exit code and fails the test if it is not zero.

    def test_set(self):
        """
        Test setting values, then perform a get to verify the value.
        """
        # External IPv4.
        test_ipv4 = '208.118.235.148'
        set_args = self.get_cmd_args('set')
        set_args.extend(('/softwire-config/external-interface/ip', test_ipv4))
        self.run_cmd(set_args)
        get_args = list(set_args)[:-1]
        get_args[2] = 'get'
        output = self.run_cmd(get_args)
        self.assertEqual(
            output.strip(), bytes(test_ipv4, ENC),
            '\n'.join(('OUTPUT', str(output, ENC))))

        # Binding table.
        test_ipv4, test_ipv6, test_psid = '178.79.150.15', '::1', '0'
        set_args = self.get_cmd_args('set')
        # Implicit string concatenation, no summing needed.
        set_args.extend((
            '/softwire-config/binding-table/softwire[ipv4=%s][psid=%s]/b4-ipv6'
            % (test_ipv4, test_psid),
            test_ipv6,
        ))
        self.run_cmd(set_args)
        get_args = list(set_args)[:-1]
        get_args[2] = 'get'
        output = self.run_cmd(get_args)
        self.assertEqual(
            output.strip(), bytes(test_ipv6, ENC),
            '\n'.join(('OUTPUT', str(output, ENC))))

        # Check that the value we just set is the same in the IETF schema.
        # We actually need to look this up backwards, let's just check the
        # same IPv4 address as was used to set it above.
        get_args = self.get_cmd_args('get')[:-1]
        get_args.extend((
            '--schema=ietf-softwire', DAEMON_PROC_NAME,
            # Implicit string concatenation, no summing needed.
            '/softwire-config/binding/br/br-instances/'
            'br-instance[id=1]/binding-table/binding-entry'
            '[binding-ipv6info=::1]/binding-ipv4-addr',
        ))
        output = self.run_cmd(get_args)
        self.assertEqual(
            output.strip(), bytes(test_ipv4, ENC),
            '\n'.join(('OUTPUT', str(output, ENC))))

        # Check the portset: the IPv4 address alone is not unique.
        get_args = self.get_cmd_args('get')[:-1]
        get_args.extend((
            '--schema=ietf-softwire', DAEMON_PROC_NAME,
            # Implicit string concatenation, no summing needed.
            '/softwire-config/binding/br/br-instances/br-instance[id=1]/'
            'binding-table/binding-entry[binding-ipv6info=::1]/port-set/psid',
        ))
        output = self.run_cmd(get_args)
        self.assertEqual(output.strip(), bytes(test_psid, ENC),
            '\n'.join(('OUTPUT', str(output, ENC))))


if __name__ == '__main__':
    unittest.main()
