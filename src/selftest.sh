#!/bin/bash
echo "selftest: ./snabb binary portability"
echo "Scanning for symbols requiring GLIBC > 2.7"
if objdump -T snabb | \
   awk '/GLIBC/ { print $(NF-1), $NF }' | \
   grep -v 'GLIBC_2\.[0-7][\. ]'; then
    echo "^^^ Error ^^^" >&2
    echo "(You might just need to 'make clean; make' at the top level.)"
    exit 1
fi
echo "selftest: ok"
