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
apps/ipsec/test-linux-compat.sh transport aes-gcm-16-icv
echo "Probing a Linux guest through ESP in tunnel mode..."
apps/ipsec/test-linux-compat.sh tunnel aes-gcm-16-icv
echo "Probing a Linux guest through ESP in transport mode (AES 256)..."
apps/ipsec/test-linux-compat.sh transport aes-256-gcm-16-icv
echo "Probing a Linux guest through ESP in tunnel mode (AES 256)..."
apps/ipsec/test-linux-compat.sh tunnel aes-256-gcm-16-icv
