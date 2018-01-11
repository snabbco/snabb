#!/usr/bin/env bash
cd $(dirname $0)
if [ $SNABB_PCI_INTEL1G0 ] && [ $SNABB_PCI_INTEL1G1 ]; then
   TESTS1G=$(find . -executable | grep -e 'test_1g')
fi
if [ $SNABB_PCI_INTEL0 ] && [ $SNABB_PCI_INTEL1 ]; then
   TESTS10G=$(find . -executable | grep -e 'test_10g')
fi
if [ -z "$TESTS1G" ] && [ -z "$TESTS10G" ]; then
   exit $TEST_SKIPPED
fi
FILTER=${1:-.*}
TESTS=$(echo "$TESTS1G" "$TESTS10G" | grep -e "$FILTER" | sort)
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
