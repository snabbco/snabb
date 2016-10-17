#!/usr/bin/env bash

SKIPPED_CODE=43

if [[ $EUID != 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

if [[ -z "$SNABB_PCI0" ]]; then
    exit $SKIPPED_CODE
fi

if [[ -z "$SNABB_PCI1" ]]; then
    exit $SKIPPED_CODE
fi

LWAFTR_IPV6_ADDRESS=fc00::100
LWAFTR_IPV4_ADDRESS=10.0.1.1

BZ_IMAGE="$HOME/.test_env/bzImage"
HUGEPAGES_FS=/dev/hugepages
IMAGE="$HOME/.test_env/qemu.img"
MAC_ADDRESS_NET0="02:AA:AA:AA:AA:AA"
MEM=1024M
MIRROR_TAP=tap0
SNABBVMX_DIR=program/snabbvmx
PCAP_INPUT=$SNABBVMX_DIR/tests/pcap/input
PCAP_OUTPUT=$SNABBVMX_DIR/tests/pcap/output
SNABBVMX_CONF=$SNABBVMX_DIR/tests/conf/snabbvmx-lwaftr.cfg
SNABBVMX_ID=xe1
SNABB_TELNET0=5000
VHU_SOCK0=/tmp/vh1a.sock

SNABBVMX_LOG=snabbvmx.log
rm -f $SNABBVMX_LOG

# Some of these functions are from program/snabbfv/selftest.sh.
# TODO: Refactor code to a common library.

# Usage: run_telnet <port> <command> [<sleep>]
# Runs <command> on VM listening on telnet <port>. Waits <sleep> seconds
# for before closing connection. The default of <sleep> is 2.
function run_telnet {
    (echo "$2"; sleep ${3:-2}) \
        | telnet localhost $1 2>&1
}

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

function qemu_cmd {
    echo "qemu-system-x86_64 \
         -kernel ${BZ_IMAGE} -append \"earlyprintk root=/dev/vda rw console=tty0\" \
         -enable-kvm -drive format=raw,if=virtio,file=${IMAGE} \
         -M pc -smp 1 -cpu host -m ${MEM} \
         -object memory-backend-file,id=mem,size=${MEM},mem-path=${HUGEPAGES_FS},share=on \
         -numa node,memdev=mem \
         -chardev socket,id=char1,path=${VHU_SOCK0},server \
             -netdev type=vhost-user,id=net0,chardev=char1 \
             -device virtio-net-pci,netdev=net0,addr=0x8,mac=${MAC_ADDRESS_NET0} \
         -serial telnet:localhost:${SNABB_TELNET0},server,nowait \
         -display none"
}

function quit_screen { screen_id=$1
    screen -X -S "$screen_id" quit &> /dev/null
}

function run_cmd_in_screen { screen_id=$1; cmd=$2
    screen_id="${screen_id}-$$"
    quit_screen "$screen_id"
    screen -dmS "$screen_id" bash -c "$cmd >> $SNABBVMX_LOG"
}

function qemu {
    run_cmd_in_screen "qemu" "`qemu_cmd`"
}

function monitor { action=$1
    local cmd="sudo ./snabb lwaftr monitor $action"
    run_cmd_in_screen "lwaftr-monitor" "$cmd"
}

function tcpreplay { pcap=$1; pci=$2
    local cmd="sudo ./snabb packetblaster replay --no-loop $pcap $pci"
    run_cmd_in_screen "tcpreplay" "$cmd"
}

function start_test_env {
    if [[ ! -f "$IMAGE" ]]; then
       echo "Couldn't find QEMU image: $IMAGE"
       exit $SKIPPED_CODE
    fi

    # Run qemu.
    qemu

    # Wait until VMs are ready.
    wait_vm_up $SNABB_TELNET0

    # Manually set ip addresses.
    run_telnet $SNABB_TELNET0 "ifconfig eth0 up" >/dev/null
    run_telnet $SNABB_TELNET0 "ip -6 addr add $LWAFTR_IPV6_ADDRESS/64 dev eth0" >/dev/null
    run_telnet $SNABB_TELNET0 "ip addr add $LWAFTR_IPV4_ADDRESS/24 dev eth0" >/dev/null
    run_telnet $SNABB_TELNET0 "ip neigh add 10.0.1.100 lladdr 02:99:99:99:99:99 dev eth0" >/dev/null
    run_telnet $SNABB_TELNET0 "ip -6 neigh add fc00::1 lladdr 02:99:99:99:99:99 dev eth0" >/dev/null
    run_telnet $SNABB_TELNET0 "route add default gw 10.0.1.100 eth0" >/dev/null
    run_telnet $SNABB_TELNET0 "route -6 add default gw fc00::1 eth0" >/dev/null
    run_telnet $SNABB_TELNET0 "sysctl -w net.ipv4.conf.all.forwarding=1" >/dev/null
    run_telnet $SNABB_TELNET0 "sysctl -w net.ipv6.conf.all.forwarding=1" >/dev/null
}

function create_mirror_tap_if_needed {
    ip tuntap add $MIRROR_TAP mode tap 2>/dev/null
    ip li set dev $MIRROR_TAP up 2>/dev/null
    ip li sh $MIRROR_TAP &>/dev/null
    if [[ $? -ne 0 ]]; then
        echo "Couldn't create mirror tap: $MIRROR_TAP"
        exit 1
    fi
}

function run_snabbvmx {
    echo "Launch Snabbvmx"
    local cmd="./snabb snabbvmx lwaftr --conf $SNABBVMX_CONF --id $SNABBVMX_ID \
        --pci $SNABB_PCI0 --mac $MAC_ADDRESS_NET0 --sock $VHU_SOCK0 \
        --mirror $MIRROR_TAP "
    run_cmd_in_screen "snabbvmx" "$cmd"
}

function capture_mirror_tap_to_file { fileout=$1; filter=$2
    local cmd=""
    if [[ -n $filter ]]; then
        cmd="sudo tcpdump \"${filter}\" -U -c 1 -i $MIRROR_TAP -w $fileout"
    else
        cmd="sudo tcpdump -U -c 1 -i $MIRROR_TAP -w $fileout"
    fi
    run_cmd_in_screen "tcpdump" "$cmd"
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

function pcap2text { pcap=$1; txt=$2
    filesize=$(ls -l $pcap | awk '{ print $5 }')
    if [[ $filesize < 40 ]]; then
        # Empty file.
        rm -f $txt
        touch $txt
    else
        od -Ax -tx1 -j 40 $pcap > $txt
    fi
}

function icmpv4_cmp { pcap1=$1; pcap2=$2
    local actual=/tmp/actual.txt
    local expected=/tmp/expected.txt

    pcap2text $pcap1 $actual
    pcap2text $pcap2 $expected

    zero_identifier $actual $expected
    zero_checksum $actual $expected

    local out=$(diff $actual $expected)
    echo ${#out}
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
    local actual=/tmp/actual.txt
    local expected=/tmp/expected.txt

    pcap2text $pcap1 $actual
    pcap2text $pcap2 $expected

    local out=$(diff $actual $expected)
    echo ${#out}
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

function cleanup {
    screens=$(screen -ls | egrep -o "[0-9]+\." | sed 's/\.//')
    for each in $screens; do
        if [[ "$each" > 0 ]]; then
            screen -S $each -X quit
        fi
    done
    exit 0
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

# Set up graceful `exit'.
trap cleanup EXIT HUP INT QUIT TERM

# Run snabbvmx with VM.
create_mirror_tap_if_needed
run_snabbvmx
start_test_env

# Mirror all packets to tap0.
monitor all

test_ping_to_lwaftr_inet
test_ping_to_lwaftr_b4
test_arp_request_to_lwaftr
test_ndp_request_to_lwaftr
