#!/usr/bin/env bash
cd $(dirname $0)
[ -z $SNABB_PCI_INTEL1G0 ] && exit $TEST_SKIPPED
[ -z $SNABB_PCI_INTEL1G1 ] && exit $TEST_SKIPPED
[ -z $SNABB_PCI_INTEL0 ] && exit $TEST_SKIPPED
[ -z $SNABB_PCI_INTEL1 ] && exit $TEST_SKIPPED
FILTER=${1:-.*}
TESTS=$(find . -executable | grep -e 'test[0-9]' -e 'test_' | grep -e "$FILTER" | sort)
ESTATUS=0
export SNABB_RECV_DEBUG=true
export SNABB_RECV_MASTER_STATS=true
for i in $TESTS; do
   pkill -P $$ -f snabb
   sleep 1
   rm -f /var/run/snabb/intel_mp*
   rm -f results.*
   $i
   if test $? -eq 0; then
      echo "PASSED: $i"
   else
      for res in `ls results.*`; do
	      echo $res;
	      cat $res
	      echo
      done
      echo "FAILED: $i"
      ESTATUS=-1
   fi
   sleep 1
done
exit $ESTATUS
