#!/usr/bin/env bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

if [[ $1 == '-r' ]]; then
   REGEN=true
fi

function quit_with_msg {
   echo $1; exit 1
}

function scmp {
    if ! cmp $1 $2 ; then
        ls -l $1
        ls -l $2
        quit_with_msg "$3"
    fi
}

function snabb_run_and_cmp_two_interfaces {
   conf=$1; v4_in=$2; v6_in=$3; v4_out=$4; v6_out=$5; counters_path=$6;
   endoutv4="${TEST_OUT}/endoutv4.pcap"; endoutv6="${TEST_OUT}/endoutv6.pcap";
   rm -f $endoutv4 $endoutv6
   ${SNABB_LWAFTR} check \
      $conf $v4_in $v6_in \
      $endoutv4 $endoutv6 $counters_path || quit_with_msg \
         "Failure: ${SNABB_LWAFTR} check $*"
   scmp $v4_out $endoutv4 \
      "Failure: ${SNABB_LWAFTR} check $*"
   scmp $v6_out $endoutv6 \
      "Failure: ${SNABB_LWAFTR} check $*"
   echo "Test passed"
}

function snabb_run_and_regen_counters {
   conf=$1; v4_in=$2; v6_in=$3; v4_out=$4; v6_out=$5; counters_path=$6;
   endoutv4="${TEST_OUT}/endoutv4.pcap"; endoutv6="${TEST_OUT}/endoutv6.pcap";
   rm -f $endoutv4 $endoutv6
   ${SNABB_LWAFTR} check -r \
      $conf $v4_in $v6_in \
      $endoutv4 $endoutv6 $counters_path || quit_with_msg \
         "Failed to regen counters:\n\t ${SNABB_LWAFTR} check $*"
   echo "Regenerated counters"
}

function is_packet_in_wrong_interface_test {
    counters_path=$1
    if [[ "$counters_path" == "${COUNTERS}/non-ipv6-traffic-to-ipv6-interface.lua" ||
          "$counters_path" == "${COUNTERS}/non-ipv4-traffic-to-ipv4-interface.lua" ]]; then
        echo 1
    fi
}

function snabb_run_and_cmp_on_a_stick {
   conf=$1; v4_in=$2; v6_in=$3; v4_out=$4; v6_out=$5; counters_path=$6
   endoutv4="${TEST_OUT}/endoutv4.pcap"; endoutv6="${TEST_OUT}/endoutv6.pcap"
   # Skip these tests as they will fail in on-a-stick mode.
   if [[ $(is_packet_in_wrong_interface_test $counters_path) ]]; then
       echo "Test skipped"
       return
   fi
   rm -f $endoutv4 $endoutv6
   ${SNABB_LWAFTR} check --on-a-stick \
      $conf $v4_in $v6_in \
      $endoutv4 $endoutv6 $counters_path || quit_with_msg \
         "Failure: ${SNABB_LWAFTR} check --on-a-stick $*"
   scmp $v4_out $endoutv4 \
      "Failure: ${SNABB_LWAFTR} check --on-a-stick $*"
   scmp $v6_out $endoutv6 \
      "Failure: ${SNABB_LWAFTR} check --on-a-stick $*"
   echo "Test passed"
}

function snabb_run_and_cmp {
   if [ -z $6 ]; then
      echo "not enough arguments to snabb_run_and_cmp"
      exit 1
   fi
   if [ $REGEN ] ; then
      snabb_run_and_regen_counters $@
   else
      snabb_run_and_cmp_two_interfaces $@
      snabb_run_and_cmp_on_a_stick $@
   fi
}

source "test_env.sh"

TEST_OUT="/tmp"
SNABB_LWAFTR="../../../../snabb lwaftr"

while true; do
    print_test_name
    snabb_run_and_cmp $(read_test_data)
    next_test || break
done
echo "All end-to-end lwAFTR tests passed."
