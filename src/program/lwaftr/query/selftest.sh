#!/usr/bin/env bash

LWAFTR_DIR="./program/lwaftr"

# Pass TEST_DIR and QUERY_TEST_DIR to the invoked scripts.
export TEST_DIR="${LWAFTR_DIR}/tests"
export QUERY_TEST_DIR="${LWAFTR_DIR}/query/tests"

${QUERY_TEST_DIR}/test_query.sh
${QUERY_TEST_DIR}/test_query_reconfigurable.sh
