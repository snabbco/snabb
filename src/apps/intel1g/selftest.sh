#!/usr/bin/env bash
cd $(dirname $0)
[ -z $SNABB_PCI_INTEL1G0 ] && exit $TEST_SKIPPED
[ -z $SNABB_PCI_INTEL1G1 ] && exit $TEST_SKIPPED
TESTS=$(find . -executable | grep -Pe 'test\d+\.')
ESTATUS=0
for i in $TESTS; do
   $i
   if test $? -ne 0; then
      echo "test $i failed"
      ESTATUS=-1
   fi
done
exit $ESTATUS
