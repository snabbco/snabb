#!/bin/bash
echo "selftest: ./snabb binary portability"
glibc=$(objdump -T snabb | grep GLIBC | sed -e 's/^.*GLIBC_//' -e 's/ .*//' | sort -nr | head -1)
if [ "$glibc" == "2.7" ]; then
    echo "ok: links with glibc >= 2.7"
else
    echo "error: requires glibc $glibc (> 2.7)"
    exit 1
fi
