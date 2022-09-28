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
import re
import random
import string

from test_env import BENCHDATA_DIR, DATA_DIR, ENC, SNABB_CMD, \
                     DAEMON_STARTUP_WAIT, BaseTestCase, nic_names

DAEMON_PROC_NAME = 'config-test-daemon'
DAEMON_ARGS = [
    str(SNABB_CMD), 'lwaftr', 'bench',
    '--bench-file', '/dev/null',
    '--name', DAEMON_PROC_NAME,
    str(DATA_DIR / 'icmp_on_fail.conf'),
    str(BENCHDATA_DIR / 'ipv4-0550.pcap'),
    str(BENCHDATA_DIR / 'ipv6-0550.pcap'),
]
LISTEN_SOCKET_PATH = '/tmp/snabb-lwaftr-listen-sock-%s' % DAEMON_PROC_NAME
MANAGER_SOCKET_PATH = '/var/run/snabb/by-name/%s/config-leader-socket' % DAEMON_PROC_NAME

def random_string(n=8):
    return ''.join(random.choice(string.ascii_uppercase + string.digits) for _ in range(n))

def set_random_name(test):
    global DAEMON_PROC_NAME
    global LISTEN_SOCKET_PATH
    global MANAGER_SOCKET_PATH

    # Create random name.
    name = 'config-test-daemon-' + random_string()

    DAEMON_PROC_NAME = name
    LISTEN_SOCKET_PATH = '/tmp/snabb-lwaftr-listen-sock-%s' % DAEMON_PROC_NAME
    MANAGER_SOCKET_PATH = '/var/run/snabb/by-name/%s/config-leader-socket' % DAEMON_PROC_NAME

    # Update test arguments name.
    test.daemon_args[6] = name
    test.config_args = list(test.config_args)
    test.config_args[4] = name

def wait_for_socket(socket_path, timeout=5, step=0.1):
    for i in range(0, int(timeout/step)):
        if os.access(socket_path, os.F_OK):
            return True
        time.sleep(step)
    return False

def wait_for_listen_socket(**kwargs):
    return wait_for_socket(LISTEN_SOCKET_PATH, **kwargs)
def wait_for_manager_socket(**kwargs):
    return wait_for_socket(MANAGER_SOCKET_PATH, **kwargs)

class TestConfigGet(BaseTestCase):
    """
    Test querying from a known config, testing basic "getting".
    It performs numerous gets on different paths.
    """

    daemon_args = DAEMON_ARGS
    config_args = (str(SNABB_CMD), 'config', 'get', '--schema=snabb-softwire-v3', DAEMON_PROC_NAME)

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        if not wait_for_manager_socket():
            cls.daemon.terminate()
            cls.reportAndFail('Config manager socket not present', None)

    def test_get_internal_iface(self):
        cmd_args = list(self.config_args)
        cmd_args.append('/softwire-config/instance[device=test]/queue[id=0]'
                        '/internal-interface/ip')
        output = self.run_cmd(cmd_args)
        self.assertEqual(
            output.strip(), b'8:9:a:b:c:d:e:f',
            '\n'.join(('OUTPUT', str(output, ENC))))

    def test_get_external_iface(self):
        cmd_args = list(self.config_args)
        cmd_args.append('/softwire-config/instance[device=test]/queue[id=0]/'
                        'external-interface/ip')
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
        cmd_args[3] = '--schema=ietf-softwire-br'
        cmd_args.extend((
            DAEMON_PROC_NAME,
            # Implicit string concatenation, do not add commas.
            '/br-instances/binding/'
            'bind-instance[name=config-test-daemon]/binding-table/binding-entry'
            '[binding-ipv6info=127:22:33:44:55:66:77:128]/binding-ipv4-addr',
        ))
        output = self.run_cmd(cmd_args)
        self.assertEqual(
            output.strip(), b'178.79.150.15',
            '\n'.join(('OUTPUT', str(output, ENC))))


class TestConfigMultiproc(BaseTestCase):
    """
    Test the ability to start, stop, get, etc. multiple processes.
    """

    daemon = None
    daemon_args = DAEMON_ARGS
    ps_args = (str(SNABB_CMD), 'ps')
    config_args = (str(SNABB_CMD), 'config', 'XXX', '--schema=snabb-softwire-v3', DAEMON_PROC_NAME)

    @classmethod
    def setUpClass(cls):
        pass

    @classmethod
    def tearDownClass(cls):
        pass

    def start_daemon(self, config, additional=None):
        """ Starts the daemon with a specific config """
        if self.daemon is not None:
            raise Exception("Daemon already started")

        set_random_name(self)

        daemon_args = list(self.daemon_args)
        daemon_args[7] = config
        for option in (additional or []):
            daemon_args.insert(3, option)

        # Start the daemon itself
        self.daemon = Popen(daemon_args, stdout=PIPE, stderr=PIPE)
        if not wait_for_manager_socket():
            self.daemon.terminate()
            stdout = self.daemon.stdout.read().decode(ENC)
            stderr = self.daemon.stderr.read().decode(ENC)
            self.fail("\n".join((
                "Failed starting daemon",
                "Command:", " ".join(daemon_args),
                "STDOUT", stdout,
                "STDOUT", stderr,
            )))
        return self.daemon.pid

    @property
    def instances(self):
        """ Gets list of all the instance PIDs for lwaftr """
        mypid = self.daemon.pid
        output = self.run_cmd(self.ps_args).decode("utf-8")
        my_lines = [inst for inst in output.split("\n") if str(mypid) in inst]

        # The list won't be clean and have lots of text, extract the PIDs
        instances = {}
        for inst in my_lines:
            # parts example: ['\\-', '20422', 'worker', 'for', '20420']
            parts = inst.split()
            if parts[0] == "\\-":
                instances[int(parts[-1])].add(int(parts[1]))
            else:
                instances[int(parts[0])] = set()

        return instances


    def tearDown(self):
        self.stop_daemon(self.daemon)
        self.daemon = None
        return super().tearDown()

    def test_start_empty(self):
        config = str(DATA_DIR / "empty.conf")
        pid = self.start_daemon(config)
        self.assertEqual(len(self.instances[pid]), 0)


    def test_added_instances_startup(self):
        config = str(DATA_DIR / "icmp_on_fail.conf")
        pid = self.start_daemon(config)
        initial_instance_amount = len(self.instances[pid])

        # add an instance
        device = """{
        device addtest1;
        queue {
          id 0;
          external-interface {
            ip 72.72.72.72;
            mac 14:14:14:14:14:14;
            next-hop {
              mac 15:15:15:15:15:15;
            }
          }
          internal-interface {
            ip 7:8:9:A:B:C:D:E;
            mac 16:16:16:16:16:16;
            next-hop {
              mac 17:17:17:17:17:17;
            }
          }
        }}"""
        config_add_cmd = list(self.config_args)
        config_add_cmd[2] = 'add'
        config_add_cmd.extend((
            '/softwire-config/instance',
            device
        ))

        # Add the instance
        self.run_cmd(config_add_cmd)

        # Wait around for it to start the instance
        time.sleep(1)

        # Verify we've got one more instance
        self.assertEqual(
            len(self.instances[pid]), (initial_instance_amount + 1)
        )

    def test_removed_instances_shutdown(self):
        config = str(DATA_DIR / "icmp_on_fail.conf")
        pid = self.start_daemon(config)
        initial_instance_amount = len(self.instances[pid])

        # There should be an instance called "test" in the initial
        # config that's loaded. We'll try removing that.
        config_remove_cmd = list(self.config_args)
        config_remove_cmd[2] = 'remove'
        config_remove_cmd.append('/softwire-config/instance[device=test]')

        # Remove it
        self.run_cmd(config_remove_cmd)

        # Wait for the isntance to shutdown
        time.sleep(1)

        # Verify we've got one less instance than when we started.
        self.assertEqual(
            len(self.instances[pid]), (initial_instance_amount - 1)
        )

    def test_snabb_get_state_summation(self):
        config = str(DATA_DIR / "icmp_on_fail_multiproc.conf")
        pid = self.start_daemon(config)

        get_state_cmd = list(self.config_args)
        get_state_cmd[2] = "get-state"
        get_state_cmd.insert(4, "-f")
        get_state_cmd.insert(5, "xpath")
        get_state_cmd.append("/")

        state = self.run_cmd(get_state_cmd).decode(ENC)
        state = [line for line in state.split("\n") if line]

        # Build two dictionaries, one of each instance counter (a total)
        # and one of just the values in the global "softwire-state"
        summed = {}
        instance = {}
        for line in state:
            if "softwire-state" not in line:
                continue
            [cname, cvalue] = line.split(" ")
            cname = os.path.basename(cname)
            if cname == "discontinuity-time":
                cvalue = str(cvalue)
                continue
            cvalue = int(cvalue)

            if line.startswith("/softwire-config"):
                instance[cname] = instance.get(cname, 0) + cvalue
            elif line.startswith("/softwire-state"):
                summed[cname] = cvalue

        # Now assert they're the same :)
        for name, value in summed.items():
            self.assertEqual(value, instance[name])

    def test_snabb_get_state_lists_instances(self):
        config = str(DATA_DIR / "icmp_on_fail_multiproc.conf")
        pid = self.start_daemon(config)

        get_state_cmd = list(self.config_args)
        get_state_cmd[2] = "get-state"
        get_state_cmd.insert(4, "-f")
        get_state_cmd.insert(5, "xpath")
        get_state_cmd.append("/")

        state = self.run_cmd(get_state_cmd).decode(ENC)
        state = [line for line in state.split("\n") if line]

        instances = set()
        for line in state:
            [key, value] = line.split(" ")
            if key.startswith("/softwire-config") and "instance" not in key:
                continue
            m = re.search(r"\[device=(.*)\]", key)
            if m:
                device_name = m.group(1)
                instances.add(device_name)

        self.assertTrue(len(instances) == 2)
        self.assertTrue("test" in instances)
        self.assertTrue("test1" in instances)


class TestConfigListen(BaseTestCase):
    """
    Test it can listen, send a command and get a response. Only test the
    socket method of communicating with the listen command, due to the
    difficulties of testing interactive scripts.
    """

    daemon_args = DAEMON_ARGS
    listen_args = (str(SNABB_CMD), 'config', 'listen',
        '--socket', LISTEN_SOCKET_PATH, DAEMON_PROC_NAME)

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        if not wait_for_manager_socket():
            cls.daemon.terminate()
            cls.reportAndFail('Config manager socket not present', None)

    def test_listen(self):
        # Start the listen command with a socket.
        listen_daemon = Popen(self.listen_args, stdout=PIPE, stderr=PIPE)
        if not wait_for_listen_socket():
            listen_daemon.terminate()
            listen_daemon.wait()
            stdout = listen_daemon.stdout.read().decode(ENC)
            stderr = listen_daemon.stderr.read().decode(ENC)
            self.fail("\n".join((
                "Failed to run 'snabb listen'",
                "Command:", " ".join(self.daemon_args),
                "STDOUT", stdout,
                "STDOUT", stderr,
            )))
        # Send command to and receive response from the listen command.
        # (Implicit string concatenation, no summing needed.)
        get_cmd = (b'{ "id": "0", "verb": "get",'
            b' "path": "/routes/route[addr=1.2.3.4]/port" }\n')
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            sock.connect(LISTEN_SOCKET_PATH)
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
        os.unlink(LISTEN_SOCKET_PATH)


class TestConfigMisc(BaseTestCase):

    daemon_args = DAEMON_ARGS

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        if not wait_for_manager_socket():
            cls.daemon.terminate()
            cls.reportAndFail('Config manager socket not present', None)

    def get_cmd_args(self, action):
        cmd_args = list((str(SNABB_CMD), 'config', 'XXX', '--schema=snabb-softwire-v3', DAEMON_PROC_NAME))
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
            '{ ipv4 8.8.8.8; psid 7; b4-ipv6 ::2; br-address 2001:db8::;'
            'port-set { psid-length 16; }}',
        ))
        self.run_cmd(add_args)
        get_args = self.get_cmd_args('get')
        get_args.append(
            '/softwire-config/binding-table/softwire[ipv4=8.8.8.8][psid=7]'
            '/b4-ipv6')
        output = self.run_cmd(get_args)
        # run_cmd checks the exit code and fails the test if it is not zero.
        self.assertEqual(
            output.strip(), b'::2',
            '\n'.join(('OUTPUT', str(output, ENC))))

    def test_add_ietf(self):
        add_args = self.get_cmd_args('add')[:-1]
        add_args[3] = '--schema=ietf-softwire-br'
        add_args.extend((
            DAEMON_PROC_NAME,
            # Implicit string concatenation, no summing needed.
            '/br-instances/binding/bind-instance[name=config-test-daemon]/'
            'binding-table/binding-entry',
            '{ binding-ipv6info ::123; binding-ipv4-addr 8.8.8.8;'
            'br-ipv6-addr 2001:db8::; port-set { psid 8; psid-len 15; }}',
        ))
        self.run_cmd(add_args)
        get_args = self.get_cmd_args('get')[:-1]
        get_args[3] = '--schema=ietf-softwire-br'
        get_args.extend((
            DAEMON_PROC_NAME,
            '/br-instances/binding/bind-instance[name=config-test-daemon]/'
            'binding-table/binding-entry[binding-ipv6info=::123]/port-set/psid',
        ))
        output = self.run_cmd(get_args)
        # run_cmd checks the exit code and fails the test if it is not zero.
        self.assertEqual(
            output.strip(), b'8',
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

    def test_get_state_ietf(self):
        get_args = self.get_cmd_args('get-state')[:-1]
        get_args[3] = '--schema=ietf-softwire-br'
        get_args.extend((
            DAEMON_PROC_NAME,
            '/br-instances/binding/bind-instance[name=config-test-daemon]/'
            'traffic-stat/rcvd-ipv4-bytes',
        ))
        output = self.run_cmd(get_args)
        # run_cmd checks the exit code and fails the test if it is not zero.
        self.assertNotEqual(
            output.strip(), b'0',
            '\n'.join(('OUTPUT', str(output, ENC))))

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
        self.run_cmd(remove_args)
        # run_cmd checks the exit code and fails the test if it is not zero.
        # Verify we cannot find it anymore.
        self.run_cmd(get_args, 1)
        # run_cmd checks the exit code and fails the test if it is not 1.

    def test_remove_ietf(self):
        # Verify that the thing we want to remove actually exists.
        get_args = self.get_cmd_args('get')[:-1]
        get_args[3] = '--schema=ietf-softwire-br'
        get_args.extend((
            DAEMON_PROC_NAME,
            '/br-instances/binding/bind-instance[name=config-test-daemon]/'
            'binding-table/binding-entry[binding-ipv6info=::123]',
        ))
        self.run_cmd(get_args)
        # run_cmd checks the exit code and fails the test if it is not zero.
        # Remove it.
        remove_args = list(get_args)
        remove_args[2] = 'remove'
        self.run_cmd(remove_args)
        # run_cmd checks the exit code and fails the test if it is not zero.
        # Verify we cannot find it anymore.
        self.run_cmd(get_args, 1)
        # run_cmd checks the exit code and fails the test if it is not 1.x

    def test_set(self):
        """
        Test setting values, then perform a get to verify the value.
        """
        # External IPv4.
        test_ipv4 = '208.118.235.148'
        set_args = self.get_cmd_args('set')
        set_args.extend((
            "/softwire-config/instance[device=test]/queue[id=0]/"
            "external-interface/ip", test_ipv4
        ))
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
        get_args[3] = '--schema=ietf-softwire-br'
        get_args.extend((
            DAEMON_PROC_NAME,
            # Implicit string concatenation, no summing needed.
            '/br-instances/binding/'
            'bind-instance[name=config-test-daemon]/binding-table/binding-entry'
            '[binding-ipv6info=::1]/binding-ipv4-addr',
        ))
        output = self.run_cmd(get_args)
        self.assertEqual(
            output.strip(), bytes(test_ipv4, ENC),
            '\n'.join(('OUTPUT', str(output, ENC))))

        # Check the portset: the IPv4 address alone is not unique.
        get_args = self.get_cmd_args('get')[:-1]
        get_args[3] = '--schema=ietf-softwire-br'
        get_args.extend((
            DAEMON_PROC_NAME,
            # Implicit string concatenation, no summing needed.
            '/br-instances/binding/bind-instance[name=config-test-daemon]/'
            'binding-table/binding-entry[binding-ipv6info=::1]/port-set/psid',
        ))
        output = self.run_cmd(get_args)
        self.assertEqual(output.strip(), bytes(test_psid, ENC),
            '\n'.join(('OUTPUT', str(output, ENC))))

    def test_set_ietf(self):
        """
        Set binding table, update an entry, check for validity via get.
        """
        set_args = self.get_cmd_args('set')[:-1]
        set_args[3] = '--schema=ietf-softwire-br'
        set_args.extend((
            DAEMON_PROC_NAME,
            # Implicit string concatenation, no summing needed.
            '/br-instances/binding/bind-instance[name=config-test-daemon]/'
            'binding-table/binding-entry',
            '{ binding-ipv6info ::124; binding-ipv4-addr 8.8.8.8;'
            'br-ipv6-addr 2001:db8::; port-set { psid 8; psid-len 15; }}',
        ))
        self.run_cmd(set_args)
        set_args = self.get_cmd_args('set')[:-1]
        set_args[3] = '--schema=ietf-softwire-br'
        set_args.extend((
            DAEMON_PROC_NAME,
            # Implicit string concatenation, no summing needed.
            '/br-instances/binding/bind-instance[name=config-test-daemon]/'
            'binding-table/binding-entry[binding-ipv6info=::124]/'
            'binding-ipv4-addr',
            '9.9.9.9',
        ))
        self.run_cmd(set_args)
        get_args = self.get_cmd_args('get')
        get_args.append(
            '/softwire-config/binding-table/softwire[ipv4=9.9.9.9][psid=8]'
            '/b4-ipv6')
        output = self.run_cmd(get_args)
        # run_cmd checks the exit code and fails the test if it is not zero.
        self.assertEqual(
            output.strip(), b'::124',
            '\n'.join(('OUTPUT', str(output, ENC))))

    def test_set_ietf_special(self):
        """
        Test handling of special br attributes.
        """
        set_args = self.get_cmd_args('set')[:-1]
        set_args[3] = '--schema=ietf-softwire-br'
        set_args.extend((
            DAEMON_PROC_NAME,
            # Implicit string concatenation, no summing needed.
            '/br-instances/binding/bind-instance[name=config-test-daemon]/'
            'softwire-path-mru',
            '542',
        ))
        self.run_cmd(set_args)
        get_args = self.get_cmd_args('get')[:-1]
        get_args[3] = '--schema=ietf-softwire-br'
        get_args.extend((
            DAEMON_PROC_NAME,
            '/br-instances/binding/bind-instance[name=config-test-daemon]/'
            'softwire-path-mru',
        ))
        output = self.run_cmd(get_args)
        # run_cmd checks the exit code and fails the test if it is not zero.
        self.assertEqual(
            output.strip(), b'542',
            '\n'.join(('OUTPUT', str(output, ENC))))
        #####
        set_args = self.get_cmd_args('set')[:-1]
        set_args[3] = '--schema=ietf-softwire-br'
        set_args.extend((
            DAEMON_PROC_NAME,
            # Implicit string concatenation, no summing needed.
            '/br-instances/binding/bind-instance[name=config-test-daemon]/'
            'icmp-policy/icmpv6-errors/generate-icmpv6-errors',
            'false',
        ))
        self.run_cmd(set_args)
        get_args = self.get_cmd_args('get')[:-1]
        get_args[3] = '--schema=ietf-softwire-br'
        get_args.extend((
            DAEMON_PROC_NAME,
            '/br-instances/binding/bind-instance[name=config-test-daemon]/'
            'icmp-policy/icmpv6-errors/generate-icmpv6-errors',
        ))
        output = self.run_cmd(get_args)
        # run_cmd checks the exit code and fails the test if it is not zero.
        self.assertEqual(
            output.strip(), b'false',
            '\n'.join(('OUTPUT', str(output, ENC))))
        #####
        set_args = self.get_cmd_args('set')[:-1]
        set_args[3] = '--schema=ietf-softwire-br'
        set_args.extend((
            DAEMON_PROC_NAME,
            # Implicit string concatenation, no summing needed.
            '/br-instances/binding/bind-instance[name=config-test-daemon]/'
            'icmp-policy/icmpv4-errors/icmpv4-rate',
            '1001',
        ))
        self.run_cmd(set_args)
        get_args = self.get_cmd_args('get')[:-1]
        get_args[3] = '--schema=ietf-softwire-br'
        get_args.extend((
            DAEMON_PROC_NAME,
            '/br-instances/binding/bind-instance[name=config-test-daemon]/'
            'icmp-policy/icmpv4-errors/icmpv4-rate',
        ))
        output = self.run_cmd(get_args)
        # run_cmd checks the exit code and fails the test if it is not zero.
        self.assertEqual(
            output.strip(), b'1001',
            '\n'.join(('OUTPUT', str(output, ENC))))

    def test_wrong_instance_ietf(self):
        # Check for failure when querying wrong instance
        remove_args = self.get_cmd_args('remove')[:-1]
        remove_args[3] = '--schema=ietf-softwire-br'
        remove_args.extend((
            DAEMON_PROC_NAME,
            # Implicit string concatenation, no summing needed.
            '/br-instances/binding/bind-instance[name=nosuchinstance]'
            'binding-table/binding-entry[binding-ipv6info=::123]',
        ))
        output = str(self.run_cmd(remove_args, 1), ENC)
        self.assertRegex(output, 'name does not match',
            '\n'.join(('OUTPUT', output)))
        ####
        set_args = self.get_cmd_args('set')[:-1]
        set_args[3] = '--schema=ietf-softwire-br'
        set_args.extend((
            DAEMON_PROC_NAME,
            # Implicit string concatenation, no summing needed.
            '/br-instances/binding/bind-instance[name=nosuchinstance]/'
            'binding-table/binding-entry',
            '{ binding-ipv6info ::124; binding-ipv4-addr 8.8.8.8;'
            'br-ipv6-addr 2001:db8::; port-set { psid 8; psid-len 15; }}',
        ))
        output = str(self.run_cmd(set_args, 1), ENC)
        self.assertRegex(output, 'name does not match',
            '\n'.join(('OUTPUT', output)))
        ####
        set_args = self.get_cmd_args('set')[:-1]
        set_args[3] = '--schema=ietf-softwire-br'
        set_args.extend((
            DAEMON_PROC_NAME,
            # Implicit string concatenation, no summing needed.
            '/br-instances/binding/bind-instance[name=nosuchinstance]/'
            'binding-table/binding-entry[binding-ipv6info=::124]/'
            'binding-ipv4-addr',
            '9.9.9.9',
        ))
        output = str(self.run_cmd(set_args, 1), ENC)
        self.assertRegex(output, 'name does not match',
            '\n'.join(('OUTPUT', output)))
        ####
        set_args = self.get_cmd_args('set')[:-1]
        set_args[3] = '--schema=ietf-softwire-br'
        set_args.extend((
            DAEMON_PROC_NAME,
            # Implicit string concatenation, no summing needed.
            '/br-instances/binding/bind-instance[name=nosuchinstance]/'
            'icmp-policy/icmpv4-errors/icmpv4-rate',
            '1001',
        ))
        output = str(self.run_cmd(set_args, 1), ENC)
        self.assertRegex(output, 'name does not match',
            '\n'.join(('OUTPUT', output)))


if __name__ == '__main__':
    unittest.main()
