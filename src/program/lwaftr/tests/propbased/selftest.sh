#!/usr/bin/env bash

set -e

SKIPPED_CODE=43

if [ -z $SNABB_PCI0 0 ]; then exit SKIPPED_CODE; fi

./snabb quickcheck program.lwaftr.tests.propbased.prop_nocrash $SNABB_PCI0
