#!/usr/bin/env bash

set -o errexit

./program/lwaftr/tests/config/test-config-get.sh
./program/lwaftr/tests/config/test-config-set.sh
./program/lwaftr/tests/config/test-config-add.sh
./program/lwaftr/tests/config/test-config-remove.sh
./program/lwaftr/tests/config/test-config-get-state.sh
./program/lwaftr/tests/config/test-config-listen.sh
