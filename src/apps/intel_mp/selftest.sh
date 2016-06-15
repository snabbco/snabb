#!/usr/bin/env bash
cd $(dirname $0)
[ -z $SNABB_PCI_INTEL1G0 ] && exit $TEST_SKIPPED
[ -z $SNABB_PCI_INTEL1G1 ] && exit $TEST_SKIPPED
TESTS=$(find . -executable | grep -Pe 'test\d+\.' | sort)
ESTATUS=0
for i in $TESTS; do
   $i
   if test $? -eq 0; then
      echo -n "PASSED"
   else
      echo -n "FAILED"
      ESTATUS=-1
   fi
   echo " :$i"
done
rm -f results.*
exit $ESTATUS
