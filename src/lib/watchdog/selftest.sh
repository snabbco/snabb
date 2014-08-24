#!/bin/sh

./snabb ./lib/watchdog/selftest_design alert
if [ $? != 0 ]; then exit 1; fi

./snabb ./lib/watchdog/selftest_design alert_stop
if [ $? != 0 ]; then exit 1; fi

./snabb ./lib/watchdog/selftest_design alert_timeout
if [ $? != 142 ]; then exit 1; fi

./snabb ./lib/watchdog/selftest_design ualert
if [ $? != 0 ]; then exit 1; fi

./snabb ./lib/watchdog/selftest_design ualert_stop
if [ $? != 0 ]; then exit 1; fi

./snabb ./lib/watchdog/selftest_design ualert_timeout
if [ $? != 142 ]; then exit 1; fi
