#! /bin/sh
set -e

SKIPPED_CODE=43
if env LD_PRELOAD=libndpi.so true 2>&1 | grep -qi error; then
    echo "libndpi.so seems to be unavailable; skipping test"
    exit $SKIPPED_CODE
fi

mydir=$(dirname "$0")
exitcode=0
for path in "${mydir}"/*.test ; do
	if test -x "${path}" ; then
		echo "=== wall: $(basename "${path}") ==="
		"${path}" || exitcode=1
	fi
done
exit ${exitcode}
