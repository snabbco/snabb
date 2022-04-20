#!/usr/bin/env bash

# Attempt to migration from legacy to latest
LEGACY_OUT=`./snabb lwaftr migrate-configuration -f legacy \
	program/lwaftr/tests/configdata/legacy.conf`

if [[ "$?" -ne "0" ]]; then
	echo "Legacy configuration migration failed (status code != 0)"
	echo "$LEGACY_OUT"
	exit 1
fi


# Attempt to migrate part way through the chain
V320_OUT=`./snabb lwaftr migrate-configuration -f 3.2.0 \
	program/lwaftr/tests/configdata/3.2.0.conf`

if [[ "$?" -ne "0" ]]; then
	echo "3.2.0 configuration migration failed (status code != 0)"
	echo "$V320_OUT"
	exit 1
fi
