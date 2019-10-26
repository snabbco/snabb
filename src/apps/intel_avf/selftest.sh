#!/usr/bin/env bash

set -e

SKIPPED_CODE=43

if [ -z "$SNABB_AVF_PF0" ]; then
    echo "SNABB_AVF_PF0 not set, skipping tests."
    exit $SKIPPED_CODE
fi

cd "$(dirname $0)/tests"

source <(./setup.sh)
sleep 1 # FIXME: delay needed for the initial VFs to become usable.

for test in */*; do
    echo $test
    (cd "$(dirname $test)"; "./$(basename $test)")
done
