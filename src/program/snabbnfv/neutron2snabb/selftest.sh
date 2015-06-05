#!/bin/bash

echo "selftest: neutron2snabb/selftest.sh"

set -e

export TESTDIR=/tmp/snabbtest

# Database 1

mkdir -p $TESTDIR

./snabb snabbnfv neutron2snabb \
	program/snabbnfv/test_fixtures/neutron_csv $TESTDIR cdn1

diff $TESTDIR/port0 program/snabbnfv/test_fixtures/nfvconfig/reference/port0
diff $TESTDIR/port2 program/snabbnfv/test_fixtures/nfvconfig/reference/port2
echo "File contents as expected."

echo "selftest: ok"

rm -r $TESTDIR

