#!/usr/bin/env bash

set -e

SKIPPED_CODE=43

if [ -z $SNABB_PCI0 ]; then exit $SKIPPED_CODE; fi

./snabb lwaftr quickcheck program.lwaftr.tests.propbased.prop_nocrash $SNABB_PCI0
./snabb lwaftr quickcheck program.lwaftr.tests.propbased.prop_nocrash_state $SNABB_PCI0
./snabb lwaftr quickcheck program.lwaftr.tests.propbased.prop_sameval $SNABB_PCI0
