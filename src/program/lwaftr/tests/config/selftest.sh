#!/usr/bin/env bash

# Pass TEST_DIR and CONFIG_TEST_DIR to the invoked scripts.
export TEST_DIR="./program/lwaftr/tests"
export CONFIG_TEST_DIR=${TEST_DIR}/config

${CONFIG_TEST_DIR}/test-config-get.sh || exit $?
${CONFIG_TEST_DIR}/test-config-set.sh || exit $?
${CONFIG_TEST_DIR}/test-config-add.sh || exit $?
${CONFIG_TEST_DIR}/test-config-remove.sh || exit $?
${CONFIG_TEST_DIR}/test-config-get-state.sh || exit $?
${CONFIG_TEST_DIR}/test-config-listen.sh || exit $?
