#!/usr/bin/env bash
set -e

SKIPPED_CODE=43

# Requires test_env with Linux guest featuring ipsec/ESN support.
if [ -z "$SNABB_IPSEC_ENABLE_E2E_TEST" ]; then
    exit $SKIPPED_CODE
fi

if [ -z "$SNABB_TELNET0" ]; then
    export SNABB_TELNET0=5000
    echo "Defaulting to SNABB_TELNET0=$SNABB_TELNET0"
fi

echo "Probing a Linux guest through ESP in transport mode..."
apps/ipsec/test-linux-compat.sh transport
echo "Probing a Linux guest through ESP in tunnel mode..."
apps/ipsec/test-linux-compat.sh tunnel
