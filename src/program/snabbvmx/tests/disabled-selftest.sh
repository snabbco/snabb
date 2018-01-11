#!/usr/bin/env bash

# set -x

SKIPPED_CODE=43

if [[ $EUID != 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

if [[ -z "$SNABB_PCI0" ]]; then
    echo "Skip test: SNABB_PCI0 not defined"
    exit $SKIPPED_CODE
fi

if [[ -z "$SNABB_PCI1" ]]; then
    echo "Skip test: SNABB_PCI1 not defined"
    exit $SKIPPED_CODE
fi

LWAFTR_IPV4_ADDRESS=10.0.1.1
LWAFTR_IPV6_ADDRESS=fc00::100
MAC_ADDRESS_NET0=02:AA:AA:AA:AA:AA
MIRROR_TAP=tap0
NEXT_HOP_MAC=02:99:99:99:99:99
NEXT_HOP_V4=10.0.1.100
NEXT_HOP_V6=fc00::1
SNABBVMX_DIR=program/snabbvmx
PCAP_INPUT=$SNABBVMX_DIR/tests/pcap/input
PCAP_OUTPUT=$SNABBVMX_DIR/tests/pcap/output
SNABBVMX_CONF=$SNABBVMX_DIR/tests/conf/snabbvmx-lwaftr.cfg
SNABBVMX_ID=xe1
SNABB_TELNET0=5000
VHU_SOCK0=/tmp/vh1a.sock

function monitor {
    local action=$1 pid=$2
    ./snabb lwaftr monitor $action $pid &> monitor.log
}

function tcpreplay {
    pcap=$1; pci=$2
    snabb $pci "packetblaster replay --no-loop $pcap $pci"
}

function create_mirror_tap_if_needed {
    local TAP_LOG="tap0.log"
    sudo ip li delete $MIRROR_TAP &> $TAP_LOG
    sudo ip tuntap add $MIRROR_TAP mode tap &>> $TAP_LOG
    sudo ip li set dev $MIRROR_TAP up &>> $TAP_LOG
    sudo ip li sh $MIRROR_TAP &>> $TAP_LOG
    if [[ $? -ne 0 ]]; then
        echo "Couldn't create mirror tap: $MIRROR_TAP"
        exit 1
    fi
}

function capture_mirror_tap_to_file {
    fileout=$1; filter=$2
    if [[ -n $filter ]]; then
        tmux_launch "tcpdump" "tcpdump \"${filter}\" -U -c 1 -i $MIRROR_TAP -w $fileout"
    else
        tmux_launch "tcpdump" "tcpdump -U -c 1 -i $MIRROR_TAP -w $fileout"
    fi
    count=$((count + 1))
}

function myseq { from=$1; to=$2
    if [[ -z $to ]]; then
        to=$from
    fi
    seq $from $to
}

# Zeroes columns at rows in file.

# File should be a pcap2text file produced with 'od -Ax -tx1'
# Row and column can be single numbers or a number sequence such as '1-10'
# The function produces an awk program like:
#
#   'FNR==row_1,FNR==row_n {$column_1=column_n=00}1'
function zero { file=$1; row=$2; column=$3
    # Prepare head.
    local head=""
    row=${row/-/ }
    for each in $(myseq $row); do
        head="${head}FNR==$each,"
    done
    head=${head::-1} # Remove last character.

    # Prepare body.
    local body=""
    column=${column/-/ }
    for each in $(myseq $column); do
        body="$body\$$each="
    done
    body="${body}\"00\""

    local cmd="awk '$head {$body}1' $file > \"${file}.tmp\""
    eval $cmd
    mv "${file}.tmp" "$file"
}

function zero_identifier { file=$1; row=$2; column=$3
    for each in "$@"; do
        zero "$each" "2" "4-5"
    done
}

function zero_checksum { file=$1; row=$2; column=$3
    for each in "$@"; do
        zero "$each" "2" "10-11"
    done
}

function filesize { filename=$1
    echo $(ls -l $filename | awk '{ print $5 }')
}

function pcap2text { pcap=$1; txt=$2
    if [[ $(filesize $pcap) < 40 ]]; then
        # Empty file.
        rm -f $txt
        touch $txt
    else
        od -Ax -tx1 -j 40 $pcap > $txt
    fi
}

function icmpv4_cmp { pcap1=$1; pcap2=$2
    local ret=0

    # Compare filesize.
    if [[ $(filesize $pcap1) != $(filesize $pcap2) ]]; then
        ret=1
    else
        local actual=/tmp/actual.txt
        local expected=/tmp/expected.txt

        pcap2text $pcap1 $actual
        pcap2text $pcap2 $expected

        zero_identifier $actual $expected
        zero_checksum $actual $expected

        local out=$(diff $actual $expected)
        ret=${#out}
    fi
    echo $ret
}

function check_icmpv4_equals { testname=$1; output=$2; expected=$3
    local ret=$(icmpv4_cmp $output $expected)
    rm -f $output
    if [[ $ret == 0 ]]; then
        echo "$testname: OK"
    else
        echo "Error: '$testname' failed"
        echo -e $ret
        exit 1
    fi
}

function run_icmpv4_test { testname=$1; input=$2; expected=$3; filter=$4
    local output="/tmp/output.pcap"
    capture_mirror_tap_to_file $output "$filter"
    tcpreplay $input $SNABB_PCI1
    sleep 5
    check_icmpv4_equals "$testname" $output $expected
}

function pcap_cmp { pcap1=$1; pcap2=$2
    local ret=0
    if [[ $(filesize $pcap1) != $(filesize $pcap2) ]]; then
        ret=1
    else
        local actual=/tmp/actual.txt
        local expected=/tmp/expected.txt

        pcap2text $pcap1 $actual
        pcap2text $pcap2 $expected

        local out=$(diff $actual $expected)
        ret=${#out}
    fi
    echo $ret
}

function check_pcap_equals { testname=$1; output=$2; expected=$3
    local ret=$(pcap_cmp $output $expected)
    rm -f $output
    if [[ $ret == 0 ]]; then
        echo "$testname: OK"
    else
        echo "Error: '$testname' failed"
        echo -e $ret
        exit 1
    fi
}

function run_pcap_test { testname=$1; input=$2; expected=$3; filter=$4
    local output="/tmp/output.pcap"
    capture_mirror_tap_to_file $output "$filter"
    tcpreplay $input $SNABB_PCI1
    sleep 5
    check_pcap_equals "$testname" $output $expected
}

function test_ping_to_lwaftr_inet {
    run_icmpv4_test "Ping to lwAFTR inet side"                      \
                    "$PCAP_INPUT/ping-request-to-lwAFTR-inet.pcap"  \
                    "$PCAP_OUTPUT/ping-reply-from-lwAFTR-inet.pcap" \
                    "icmp[icmptype] == 0"

    run_icmpv4_test "Ping to lwAFTR inet side (Good VLAN)"              \
                    "$PCAP_INPUT/vlan/ping-request-to-lwAFTR-inet.pcap" \
                    "$PCAP_OUTPUT/ping-reply-from-lwAFTR-inet.pcap"     \
                    "icmp[icmptype] == 0"

    run_pcap_test   "Ping to lwAFTR inet side (Bad VLAN)"                   \
                    "$PCAP_INPUT/vlan-bad/ping-request-to-lwAFTR-inet.pcap" \
                    "$PCAP_OUTPUT/empty.pcap"
}

function test_ping_to_lwaftr_b4 {
    run_pcap_test "Ping to lwAFTR B4 side"                      \
                  "$PCAP_INPUT/ping-request-to-lwAFTR-b4.pcap"  \
                  "$PCAP_OUTPUT/ping-reply-from-lwAFTR-b4.pcap" \
                  "icmp6 and ip6[40]==129"

    run_pcap_test "Ping to lwAFTR B4 side (Good VLAN)"              \
                  "$PCAP_INPUT/vlan/ping-request-to-lwAFTR-b4.pcap" \
                  "$PCAP_OUTPUT/ping-reply-from-lwAFTR-b4.pcap"     \
                  "icmp6 and ip6[40]==129"

    run_pcap_test "Ping to lwAFTR B4 side (Bad VLAN)"                   \
                  "$PCAP_INPUT/vlan-bad/ping-request-to-lwAFTR-b4.pcap" \
                  "$PCAP_OUTPUT/empty.pcap"
}

function test_arp_request_to_lwaftr {
    run_pcap_test "ARP request to lwAFTR"                   \
                  "$PCAP_INPUT/arp-request-to-lwAFTR.pcap"  \
                  "$PCAP_OUTPUT/arp-reply-from-lwAFTR.pcap" \
                  "arp[6:2] == 2"

    run_pcap_test "ARP request to lwAFTR (Good VLAN)"           \
                  "$PCAP_INPUT/vlan/arp-request-to-lwAFTR.pcap" \
                  "$PCAP_OUTPUT/arp-reply-from-lwAFTR.pcap"     \
                  "arp[6:2] == 2"

    run_pcap_test "ARP request to lwAFTR (Bad VLAN)"                \
                  "$PCAP_INPUT/vlan-bad/arp-request-to-lwAFTR.pcap" \
                  "$PCAP_OUTPUT/empty.pcap"
}

function test_ndp_request_to_lwaftr {
    run_pcap_test "NDP request to lwAFTR"                   \
                  "$PCAP_INPUT/ndp-request-to-lwAFTR.pcap"  \
                  "$PCAP_OUTPUT/ndp-reply-from-lwAFTR.pcap" \
                  "icmp6 && ip6[40] == 136"

    run_pcap_test "NDP request to lwAFTR (Good VLAN)"           \
                  "$PCAP_INPUT/vlan/ndp-request-to-lwAFTR.pcap" \
                  "$PCAP_OUTPUT/ndp-reply-from-lwAFTR.pcap"     \
                  "icmp6 && ip6[40] == 136"

    run_pcap_test "NDP request to lwAFTR (Bad VLAN)"                \
                  "$PCAP_INPUT/vlan-bad/ndp-request-to-lwAFTR.pcap" \
                  "$PCAP_OUTPUT/empty.pcap"
}

function cleanup {
    rm -f $VHU_SOCK0
    exit $1
}

function snabbvmx_pid {
    pids=$(ps aux | grep snabbvmx | awk '{print $2;}')
    for pid in ${pids[@]}; do
        if [[ -d "/var/run/snabb/$pid" ]]; then
            echo $pid
        fi
    done
}

trap cleanup EXIT HUP INT QUIT TERM

# Import SnabbVMX test_env.
if ! source program/snabbvmx/tests/test_env/test_env.sh; then
    echo "Could not load snabbvmx test_env."; exit 1
fi

# Main.

# Run SnabbVMX with VM.
create_mirror_tap_if_needed
start_test_env $MIRROR_TAP

# Mirror all packets to tap0.

SNABBVMX_PID=$(snabbvmx_pid)
monitor all $SNABBVMX_PID

# Run tests.
test_ping_to_lwaftr_inet
test_ping_to_lwaftr_b4
test_arp_request_to_lwaftr
test_ndp_request_to_lwaftr
