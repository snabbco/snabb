#!/usr/bin/env sh
for f in `find syscall -name "*.lua"` ; do grep $f rockspec/ljsyscall-scm-1.rockspec >/dev/null || echo $f "not in rockspec"; done
