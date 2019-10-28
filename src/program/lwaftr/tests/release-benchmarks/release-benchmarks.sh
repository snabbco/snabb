#! /usr/bin/env nix-shell
#! nix-shell release-benchmarks.nix -i bash
#
# This script runs the lwAFTR release benchmarks
#
# You need to set the CPU's and PCI devices when calling the script
# for the lwAFTR and the load tester. Make sure to select them keeping
# in mind the NUMA nodes. Config options:
#
# LwAFTR
# CPUs: $SNABB_LWAFTR_CPU0 (required), $SNABB_LWAFTR_CPU1,
#       $SNABB_LWAFTR_CPU2, $SNABB_LWAFTR_CPU3
# NICs: $PCI0 (required), $PCI2, $PCI4
#
# Loadtest:
# CPUs: $SNABB_LOADTEST_CPU0, $SNABB_LOADTEST_CPU1
# NICs: $PCI1 (required, CPU0), $PCI3 (CPU0), $PCI5 (CPU1), $PCI7 (CPIU1)

if [ ! $SNABB_LWAFTR_CPU0 ]; then
    echo ">> SNABB_LWAFTR_CPU0 must be set"
    exit 1
fi

if [ ! $SNABB_PCI0 ] || [ ! $SNABB_PCI1 ]; then
    echo ">> At least SNABB_PCI0 and SNABB_PCI1 must be set"
    exit 1
fi

if [ ! $SNABB_PCI2 ] || [ ! $SNABB_PCI3 ]; then
    echo ">> SNABB_PCI2 or SNABB_PCI3 not set, only running on-a-stick tests"
    ON_A_STICK_ONLY=1
fi

if [ ! $SNABB_PCI4 ] || [ ! $SNABB_PCI5 ] || [ ! $SNABB_PCI6 ] || [ ! $SNABB_PCI7 ]; then
    echo ">> SNABB_PCI4 through SNABB_PCI7 need to be set for 2 instance, 2 NIC test"
    ONE_INSTANCE_ONLY=1
else
    if [ ! $SNABB_LOADTEST_CPU0 ] || [ ! $SNABB_LOADTEST_CPU1 ]; then
        echo ">> SNABB_LOADTEST_CPU0 and SNABB_LOADTEST_CPU1 must be set for 2 instance tests"
        exit 1
    fi
fi

# directory this script lives in
# https://stackoverflow.com/questions/59895/getting-the-source-directory-of-a-bash-script-from-within
DIR=$(dirname "$(readlink -f "$0")")

# path to snabb executable
SNABB=$DIR/../../../../snabb

# config files & pcap dataset paths
FROM_B4_PCAP=$dataset/from-b4-test.pcap
FROM_INET_PCAP=$dataset/from-inet-test.pcap
FROM_INET_AND_B4_PCAP=$dataset/from-inet-and-b4-test.pcap
CONFIGS=$dataset/*.conf

# make sure lwaftr gets shut down even on interrupt
function teardown {
    [[ -n $lwaftr_pid ]] && kill $lwaftr_pid
    [[ -n $lt_pid ]] && kill $lt_pid
    [[ -n $lt_pid2 ]] && kill $lt_pid2
}

trap teardown INT TERM

TMPDIR=`mktemp -d`

# called with benchmark name, config path, args for lwAFTR, args for loadtest
# optionally args of the second loadtest
function run_benchmark {
    name="$1"
    config="$2"
    lwaftr_args="$3"
    loadtest_args="$4"
    loadtest2_args="$5"
    cpu=${6:-$SNABB_LWAFTR_CPU0}

    lwaftr_log=`mktemp -p $TMPDIR`

    # Only supply the CPU argument only if it's not already specified.
    $SNABB lwaftr run \
        --name lwaftr-release-benchmarks \
        --conf $dataset/$config $lwaftr_args > $lwaftr_log &
    lwaftr_pid=$!

    # wait briefly to let lwaftr start up
    sleep 1

    # make sure lwAFTR has't errored out, if not then exit
    if ! ps -p $lwaftr_pid > /dev/null; then
        echo ">> lwAFTR terminated unexpectedly, ending test (log: $lwaftr_log)"
        exit 1
    fi

    log=`mktemp -p $TMPDIR`
    echo ">> Running loadtest: $name (log: $log)"
    $SNABB loadtest find-limit $loadtest_args > $log &
    lt_pid=$!

    if [ ! -z "$loadtest2_args" ]; then
        log2=`mktemp -p $TMPDIR`
        echo ">> Running loadtest 2: $name (log: $log2)"
        $SNABB loadtest find-limit $loadtest2_args > $log2 &
        lt_pid2=$!
    fi

    wait $lt_pid
    status=$?
    if [ ! -z "$loadtest2_args" ]; then
        wait $lt_pid2
        status2=$?
    fi

    kill $lwaftr_pid

    if [ $status -eq 0 ]; then
        echo ">> Success: $(tail -n 1 $log)"
    else
        echo ">> Failed: $(tail -n 1 $log)"
        exit $status
    fi
    if [ ! -z "$loadtest2_args" ]; then
        if [ $status2 -eq 0 ]; then
            echo ">> Success: $(tail -n 1 $log2)"
        else
            echo ">> Failed: $(tail -n 1 $log2)"
            exit $status
        fi
    fi
}

# first ensure all configs are compiled
echo ">> Compiling configurations (may take a while)"
for conf in $CONFIGS
do
    $SNABB lwaftr compile-configuration $conf
done

if [ ! $ON_A_STICK_ONLY ]; then
    run_benchmark "1 instance, 2 NIC interface" \
                  "lwaftr.conf" \
                  "--v4 $SNABB_PCI0 --v6 $SNABB_PCI2 --cpu $SNABB_LWAFTR_CPU0" \
                  "--cpu $SNABB_LOADTEST_CPU0 \
		   $FROM_INET_PCAP NIC0 NIC1 $SNABB_PCI1 \
                   $FROM_B4_PCAP NIC1 NIC0 $SNABB_PCI3"

    run_benchmark "1 instance, 2 NIC interfaces (from config)" \
                  "lwaftr2.conf" \
                  "--v4 $SNABB_PCI0 --v6 $SNABB_PCI2 --cpu $SNABB_LWAFTR_CPU0" \
                  "--cpu $SNABB_LOADTEST_CPU0 \
		   $FROM_INET_PCAP NIC0 NIC1 $SNABB_PCI1 \
                   $FROM_B4_PCAP NIC1 NIC0 $SNABB_PCI3"
fi

run_benchmark "1 instance, 1 NIC (on a stick)" \
              "lwaftr.conf" \
              "--on-a-stick $SNABB_PCI0 --cpu $SNABB_LWAFTR_CPU0" \
              "--cpu $SNABB_LOADTEST_CPU0 $FROM_INET_AND_B4_PCAP NIC0 NIC0 $SNABB_PCI1"

run_benchmark "1 instance, 1 NIC (on-a-stick, from config file)" \
              "lwaftr3.conf" \
              "--cpu $SNABB_LWAFTR_CPU0" \
              "--cpu $SNABB_LOADTEST_CPU0 $FROM_INET_AND_B4_PCAP NIC0 NIC0 $SNABB_PCI1"

if [ ! $ONE_INSTANCE_ONLY ]; then
    run_benchmark "2 instances, 2 NICs (from config)" \
                  "lwaftr4.conf" \
                  "--cpu $SNABB_LWAFTR_CPU0,$SNABB_LWAFTR_CPU1" \
                  "--cpu $SNABB_LOADTEST_CPU0 $FROM_INET_PCAP NIC0 NIC1 $SNABB_PCI1 \
                   $FROM_B4_PCAP NIC1 NIC0 $SNABB_PCI3" \
                  "--cpu $SNABB_LOADTEST_CPU1 $FROM_INET_PCAP NIC0 NIC1 $SNABB_PCI5 \
                   $FROM_B4_PCAP NIC1 NIC0 $SNABB_PCI7"

    run_benchmark "2 instances, 1 NIC (on a stick, from config)" \
                  "lwaftr5.conf" \
                  "--cpu $SNABB_LWAFTR_CPU0,$SNABB_LWAFTR_CPU1" \
                  "--cpu $SNABB_LOADTEST_CPU0 $FROM_INET_AND_B4_PCAP NIC0 NIC0 $SNABB_PCI1" \
                  "--cpu $SNABB_LOADTEST_CPU1 $FROM_INET_AND_B4_PCAP NIC0 NIC0 $SNABB_PCI5"
fi


if [ ! $SNABB_LWAFTR_CPU1 ]; then
    echo ">> Not running RSS test, SNABB_LWAFTR_CPU1 not set"
else
    run_benchmark "1 instance, 1 NIC, 2 queues" \
                  "lwaftr6.conf" \
                  "--cpu $SNABB_LWAFTR_CPU0,$SNABB_LWAFTR_CPU1" \
                  "--cpu $SNABB_LOADTEST_CPU0 $FROM_INET_AND_B4_PCAP NIC0 NIC0 $SNABB_PCI1" \
                  "" \
                  "$SNABB_LWAFTR_CPU0,$SNABB_LWAFTR_CPU1"
fi

if [[ ! $SNABB_LWAFTR_CPU1 || ! $SNABB_LWAFTR_CPU2 || ! $SNABB_LWAFTR_CPU3 || $ON_A_STICK_ONLY ]]; then
    echo ">> Not running test for 2 instances and 4 queues. Missing LWAFTR CPUs 0,1,2 and 3 and/or"
    echo ">> not configured at least 4 NICs."
else
    run_benchmark "2 instances, 2 NIC, 4 queues" \
                  "lwaftr7.conf" \
                  "--cpu $SNABB_LWAFTR_CPU0,$SNABB_LWAFTR_CPU1,$SNABB_LWAFTR_CPU2,$SNABB_LWAFTR_CPU3" \
                  "--cpu $SNABB_LOADTEST_CPU0 $FROM_INET_AND_B4_PCAP NIC0 NIC0 $SNABB_PCI1" \
		  "--cpu $SNABB_LOADTEST_CPU1 $FROM_INET_AND_B4_PCAP NIC0 NIC0 $SNABB_PCI3"
fi
  
# cleanup
rm -r $TMPDIR
