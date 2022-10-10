#! /usr/bin/env nix-shell
#! nix-shell -i bash -p nfdump
#
# This is a test script for the IPFIX probe program that tests the
# export process with an actual flow collector.

# tap interface setup
echo "setting up tap interface"
ip tuntap add tap-snabb-ipfix mode tap
ip addr add 10.0.0.2 dev tap-snabb-ipfix
ip link set dev tap-snabb-ipfix up

function teardown {
  echo "shutting down tap interface"
  ip link del tap-snabb-ipfix
}

trap teardown EXIT

flowdir=`mktemp -d`

# Run the flow collector, output in $flowdir
nfcapd -b 10.0.0.2 -p 4739 -l $flowdir &
capd=$!

# Run probe test
./snabb snsh -t program.ipfix.tests.test

kill $capd

# Analyze with nfdump
dumpfile=`ls -1 $flowdir | head -n 1`
summary=`nfdump -r $flowdir/$dumpfile 2>&1 | grep "Summary:"`
echo $summary
numflows=`echo "${summary}" | grep -E -o -e 'total flows: ([0-9]+)' | cut -d " " -f 3`
[ $numflows -ge 25000 ]
status=$?

rm -r $flowdir
[ $status -eq 0 ] || (echo "expected at least 25000 flows"; exit 1)
