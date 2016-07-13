#!/usr/bin/env bash

SKIPPED_CODE=43

if [ -z "$SNABB_PCI0" ]; then
    export SNABB_PCI0=soft
fi
if [ -z "$SNABB_TELNET0" ]; then
    export SNABB_TELNET0=5000
    echo "Defaulting to SNABB_TELNET0=$SNABB_TELNET0"
fi
if [ -z "$SNABB_TELNET1" ]; then
    export SNABB_TELNET1=5001
    echo "Defaulting to SNABB_TELNET1=$SNABB_TELNET1"
fi
if [ -z "$SNABB_IPERF_BENCH_CONF" ]; then
    export SNABB_IPERF_BENCH_CONF=program/snabbnfv/test_fixtures/nfvconfig/test_functions/same_vlan.ports
    echo "Defaulting to SNABB_IPERF_BENCH_CONF=$SNABB_IPERF_BENCH_CONF"
fi

TESTCONFPATH="/tmp/snabb_nfv_selftest_ports.$$"
FUZZCONFPATH="/tmp/snabb_nfv_selftest_fuzz$$.ports"

# Usage: run_telnet <port> <command> [<sleep>]
# Runs <command> on VM listening on telnet <port>. Waits <sleep> seconds
# for before closing connection. The default of <sleep> is 2.
function run_telnet {
    (echo "$2"; sleep ${3:-2}) \
        | telnet localhost $1 2>&1
}

# Usage: agrep <pattern>
# Like grep from standard input except that if <pattern> doesn't match
# the whole output is printed and status code 1 is returned.
function agrep {
    input=$(cat);
    if ! echo "$input" | grep "$1"
    then
        echo "$input"
        return 1
    fi
}

# Usage: load_config <path>
# Copies <path> to TESTCONFPATH and sleeps for a bit.
function load_config {
    echo "USING $1"
    cp "$1" "$TESTCONFPATH"
    sleep 2
}

function start_test_env {
    if ! source program/snabbnfv/test_env/test_env.sh; then
        echo "Could not load test_env."; exit 1
    fi

    if ! snabb $SNABB_PCI0 "snabbnfv traffic $SNABB_PCI0 $TESTCONFPATH vhost_%s.sock"; then
        echo "Could not start snabb."; exit 1
    fi

    if ! qemu $SNABB_PCI0 vhost_A.sock $SNABB_TELNET0; then
        echo "Could not start qemu 0."; exit 1
    fi

    if ! qemu $SNABB_PCI0 vhost_B.sock $SNABB_TELNET1; then
        echo "Could not start qemu 1."; exit 1
    fi

    # Wait until VMs are ready.
    wait_vm_up $SNABB_TELNET0
    wait_vm_up $SNABB_TELNET1

    # Manually set ip addresses.
    run_telnet $SNABB_TELNET0 "ifconfig eth0 up" >/dev/null
    run_telnet $SNABB_TELNET1 "ifconfig eth0 up" >/dev/null
    run_telnet $SNABB_TELNET0 "ip -6 addr add $(ip 0) dev eth0" >/dev/null
    run_telnet $SNABB_TELNET1 "ip -6 addr add $(ip 1) dev eth0" >/dev/null
}

function cleanup {
    # Clean up temporary config location.
    rm -f "$TESTCONFPATH" "$FUZZCONFPATH"
    exit
}

# Set up graceful `exit'.
trap cleanup EXIT HUP INT QUIT TERM

# Usage: wait_vm_up <port>
# Blocks until ping to 0::0 suceeds.
function wait_vm_up {
    local timeout_counter=0
    local timeout_max=50
    echo -n "Waiting for VM listening on telnet port $1 to get ready..."
    while ( ! (run_telnet $1 "ping6 -c 1 0::0" | grep "1 received" \
        >/dev/null) ); do
        # Time out eventually.
        if [ $timeout_counter -gt $timeout_max ]; then
            echo " [TIMEOUT]"
            exit 1
        fi
        timeout_counter=$(expr $timeout_counter + 1)
        sleep 2
    done
    echo " [OK]"
}

function assert {
    if [ $2 == "0" ]; then echo "$1 succeded."
    else
        echo "$1 failed."
        echo
        echo "qemu0.log:"
        cat "qemu0.log"
        echo
        echo
        echo "qemu1.log:"
        cat "qemu1.log"
        echo
        echo
        echo "snabb0.log:"
        cat "snabb0.log"
        exit 1
    fi
}

# Usage: debug_tcpdump <telnet_port> <n>
# Capture <n> packets on eth0 for VM listening in <telnet_port> to
# /eth0.cap.
function debug_tcpdump {
    run_telnet $1 "nohup tcpdump -c $2 -i eth0 -w /eth0.cap &"
}

# Usage: test_ping <telnet_port> <dest_ip>
# Assert successful ping from VM listening on <telnet_port> to <dest_ip>.
function test_ping {
    run_telnet $1 "ping6 -c 1 $2" \
        | agrep "1 packets transmitted, 1 received"
    assert PING $?
}

# Usage: test_jumboping <telnet_port0> <telnet_port1> <dest_ip>
# Set large "jumbo" MTU to VMs listening on <telnet_port0> and
# <telnet_port1>. Assert successful jumbo ping from VM listening on
# <telnet_port0> to <dest_ip>.
function test_jumboping {
    run_telnet $1 "ip link set dev eth0 mtu 9100" >/dev/null
    run_telnet $2 "ip link set dev eth0 mtu 9100" >/dev/null
    run_telnet $1 "ping6 -s 9000 -c 1 $3" \
        | agrep "1 packets transmitted, 1 received"
    assert JUMBOPING $?
}

# Usage: test_cheksum <telnet_port>
# Assert that checksum offload is negotiated on VM listening on
# <telnet_port>.
function test_checksum {
    local out=$(run_telnet $1 "ethtool -k eth0")

    echo "$out" | agrep 'tx-checksumming: on'
    assert TX-CHECKSUMMING  $?

}

# Usage: test_iperf <telnet_port0> <telnet_port1> <dest_ip>
# Assert successful (whatever that means) iperf run with <telnet_port1>
# listening and <telnet_port0> sending to <dest_ip>.
function test_iperf {
    run_telnet $2 "nohup iperf -d -s -V &" >/dev/null
    sleep 2
    run_telnet $1 "iperf -c $3 -f g -V" 20 \
        | agrep "s/sec"
    assert IPERF $?
}

# Usage: test_rate_limited <telnet_port0> <telnet_port1> <dest_ip> <rate> <bandwidth>
# Same as `test_iperf' but run iperf in UDP mode at <bandwidth> (in Mbps)
# and assert that iperf will not exceed <rate> (in Mbps).
function test_rate_limited {
    run_telnet $2 "nohup iperf -d -s -V &" >/dev/null
    sleep 2
    iperf=$(run_telnet $1 "iperf -c $3 -u -b $5M -f m -V" 20 \
        | egrep -o '[0-9]+ Mbits/sec')
    assert "IPERF (RATE_LIMITED)" $?
    mbps_rate=$(echo "$iperf" | cut -d " " -f 1)
    echo "IPERF rate is $mbps_rate Mbits/sec ($4 Mbits/sec allowed)."
    test $mbps_rate -lt $4
    assert RATE_LIMITED $?
}

# Usage: port_probe <telnet_port0> <telnet_port1> <dest_ip> <port> [-u]
# Returns `true' if VM listening on <telnet_port0> can connect to
# <dest_ip>/<port> on VM listening on <telnet_port1>. If `-u' is appended
# UDP is used instead of TCP.
function port_probe {
    run_telnet $2 "nohup echo | nc -q 1 $5 -l $3 $4 &" 2>&1 >/dev/null
    run_telnet $1 "nc -w 1 -q 1 -v $5 $3 $4" 5 | agrep succeeded
}

function same_vlan_tests {
    load_config program/snabbnfv/test_fixtures/nfvconfig/test_functions/same_vlan.ports

    test_ping $SNABB_TELNET0 "$(ip 1)%eth0"
    test_iperf $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0"
    test_jumboping $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0"
    # Repeat iperf test now that jumbo frames are enabled
    test_iperf $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0"
    test_checksum $SNABB_TELNET0
    test_checksum $SNABB_TELNET1
}

function rate_limited_tests {
    load_config program/snabbnfv/test_fixtures/nfvconfig/test_functions/tx_rate_limit.ports

    test_ping $SNABB_TELNET0 "$(ip 1)%eth0"
    test_rate_limited $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0" 900 1000
    test_jumboping $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0"
    # Repeat iperf test now that jumbo frames are enabled
    test_rate_limited $SNABB_TELNET1 $SNABB_TELNET0 "$(ip 0)%eth0" 900 1000

    load_config program/snabbnfv/test_fixtures/nfvconfig/test_functions/rx_rate_limit.ports

    test_ping $SNABB_TELNET0 "$(ip 1)%eth0"
    test_rate_limited $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0" 1200 1000
    test_jumboping $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0"
    # Repeat iperf test now that jumbo frames are enabled
    test_rate_limited $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0" 1200 1000

}

function tunnel_tests {
    load_config program/snabbnfv/test_fixtures/nfvconfig/test_functions/tunnel.ports

    # Assert ND was successful.
    retries=0
    while true; do
        if grep "Resolved next-hop" snabb0.log; then
            assert ND 0 && break
        elif [ $retries -gt 5 ]; then assert ND 1
        else sleep 1; retries=$(expr $retries + 1)
        fi
    done

    test_ping $SNABB_TELNET0 "$(ip 1)%eth0"
    test_iperf $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0"
    test_jumboping $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0"
    # Repeat iperf test now that jumbo frames are enabled
    test_iperf $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0"
}

function filter_tests {
    load_config program/snabbnfv/test_fixtures/nfvconfig/test_functions/filter.ports

    # port B allows ICMP and TCP/12345
    # The test cases were more involved at first but I found it quite
    # hard to use netcat reliably (see `port_probe'), e.g. once you
    # listen on *any* UDP port, any subsequent netcat listens will fail?!
    #
    # If you add any test cases, make *sure* that they fail without the
    # filter enabled, e.g. watch out for false negatives! I had my fair
    # share of trouble with those.
    #
    # Regards, Max Rottenkolber <max@mr.gy>

    test_ping $SNABB_TELNET0 "$(ip 1)%eth0"

    port_probe $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0" 12345
    assert PORTPROBE $?

    # Assert TCP/12346 is filtered.
    port_probe $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0" 12346
    test 0 -ne $?
    assert FILTER $?


    load_config program/snabbnfv/test_fixtures/nfvconfig/test_functions/stateful-filter.ports

    # port B allows ICMP and TCP/12345 ingress and established egress
    # traffic.

    test_ping $SNABB_TELNET0 "$(ip 1)%eth0"

    port_probe $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0" 12345
    assert PORTPROBE $?

    # Assert TCP/12346 is filtered.
    port_probe $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0" 12348
    test 0 -ne $?
    assert FILTER $?

    # Assert non-established egress connections are filtered.
    port_probe $SNABB_TELNET1 $SNABB_TELNET0 "$(ip 0)%eth0" 12340
    test 0 -ne $?
    assert FILTER $?
}

function crypto_tests {
    load_config program/snabbnfv/test_fixtures/nfvconfig/test_functions/crypto.ports

    test_ping $SNABB_TELNET0 "$(ip 1)%eth0"
    test_iperf $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0"
    test_jumboping $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0"
    # Repeat iperf test now that jumbo frames are enabled
    test_iperf $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0"
}

# Usage: iperf_bench [<mode>] [<config>]
# Run iperf benchmark. If <mode> is "jumbo", jumboframes will be enabled.
# <config> defaults to same_vlan.ports.
function iperf_bench {
    load_config "$SNABB_IPERF_BENCH_CONF"

    if [ "$1" = "jumbo" ]; then
        test_jumboping $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0" \
            2>&1 >/dev/null
    fi
    Gbits=$(test_iperf $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0" \
        | egrep -o '[0-9\.]+ Gbits/sec' | cut -d " " -f 1)
    if [ "$1" = "jumbo" ]; then
        echo IPERF-JUMBO "$Gbits"
    else
        echo IPERF-1500 "$Gbits"
    fi
}

# Usage: fuzz_tests <n>
# Generate and test (IPERF) <n> semi-random NFV configurations.
function fuzz_tests {
    for ((n=0;n<$1;n++)); do
        ./snabb snabbnfv fuzz \
            program/snabbnfv/test_fixtures/nfvconfig/fuzz/filter2-tunnel-txrate10-ports.spec \
            $FUZZCONFPATH
        load_config $FUZZCONFPATH
        test_iperf $SNABB_TELNET0 $SNABB_TELNET1 "$(ip 1)%eth0"
    done
}

load_config program/snabbnfv/test_fixtures/nfvconfig/test_functions/other_vlan.ports
start_test_env

# Decide which mode to run (`test', `bench' or `fuzz').
case $1 in
    bench)
        iperf_bench "$2" "$3"
        ;;
    fuzz)
        fuzz_tests "$2"
        ;;
    *)
        same_vlan_tests
        rate_limited_tests
        tunnel_tests
        filter_tests
        crypto_tests
esac

exit 0
