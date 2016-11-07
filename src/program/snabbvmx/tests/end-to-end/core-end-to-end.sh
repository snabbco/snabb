#!/usr/bin/env bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

if [[ $1 == '-r' ]]; then
   REGEN=true
fi

function quit_with_msg {
   echo -e "$1"; exit 1
}

function scmp {
    if ! cmp $1 $2 ; then
        ls -l $1
        ls -l $2
        quit_with_msg "$3"
    fi
}

function run_and_cmp {
   conf=$1; v4_in=$2; v6_in=$3; v4_out=$4; v6_out=$5; counters=$6
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

function run_and_regen_counters {
   conf=$1; v4_in=$2; v6_in=$3; v4_out=$4; v6_out=$5; counters=$6
   endoutv4="${TEST_OUT}/endoutv4.pcap"; endoutv6="${TEST_OUT}/endoutv6.pcap";
   rm -f $endoutv4 $endoutv6
   ${SNABB_LWAFTR} check -r \
      $conf $v4_in $v6_in \
      $endoutv4 $endoutv6 $counters_path || quit_with_msg \
         "Failure: ${SNABB_LWAFTR} check $*"
   echo "Regenerated counters"
}

function snabbvmx_run_and_cmp {
   if [ -z $6 ]; then
      echo "Not enough arguments to snabbvmx_run_and_cmp"
      exit 1
   fi
   if [ $REGEN ] ; then
      run_and_regen_counters $@
   else
      run_and_cmp $@
   fi
}

source "test_env.sh"

TEST_OUT="/tmp"
SNABB_LWAFTR="../../../../snabb snabbvmx"

while true; do
    print_test_name
    snabbvmx_run_and_cmp $(read_test_data)
    next_test || break
done
echo "All end-to-end lwAFTR tests passed."
