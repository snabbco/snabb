#! /usr/bin/env nix-shell
#! nix-shell -i bash -p nfdump
#
# This is a test script for the IPFIX probe program that tests the
# export process with an actual flow collector.

DURATION=10
PCAP=program/wall/tests/data/http.cap

if [ -z "$SNABB_PCI0" ]; then
  echo "SNABB_PCI0 must be set"
  exit 1
fi

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

# a function that runs the test, takes the version flag as an argument
function test_probe {
  flowdir=`mktemp -d`
  version_flag=$1

  # Run the flow collector, output in $flowdir
  nfcapd -b 10.0.0.2 -p 4739 -l $flowdir &
  capd=$!

  # Run probe first
  ./snabb ipfix probe -D $DURATION -a 10.0.0.1 -c 10.0.0.2\
    $version_flag --active-timeout 5 --idle-timeout 5 -o tap $SNABB_PCI0 tap-snabb-ipfix &
  sleep 0.5

  # ... then feed it some packets
  ./snabb packetblaster replay -D $DURATION --no-loop $PCAP $SNABB_PCI1 > /dev/null

  kill $capd

  # Analyze with nfdump
  dumpfile=`ls -1 $flowdir | head -n 1`
  nfdump -r $flowdir/$dumpfile | grep "total flows: 6, total bytes: 24609, total packets: 43" > /dev/null
  status=$?

  rm -r $flowdir
  [ $status -eq 0 ] || exit 1
}

test_probe "--netflow-v9"
test_probe "--ipfix"
