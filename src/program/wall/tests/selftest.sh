#! /bin/sh
set -e
mydir=$(dirname "$0")
exitcode=0
for path in "${mydir}"/*.test ; do
	if test -x "${path}" ; then
		echo "=== wall: $(basename "${path}") ==="
		"${path}" || exitcode=1
	fi
done
exit ${exitcode}
