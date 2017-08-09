#! /usr/bin/env nix-shell
#! nix-shell -i bash -p nfdump
#
# This is a test script for the IPFIX probe program that tests the
# export process with an actual flow collector.

DURATION=10
FLOWDIR=`mktemp -d`
PCAP=program/wall/tests/data/http.cap

# tap interface setup
ip tuntap add tap-snabb-ipfix mode tap
ip addr add 10.0.0.2 dev tap-snabb-ipfix
ip link set dev tap-snabb-ipfix up

# Run the flow collector, output in $FLOWDIR
nfcapd -b 10.0.0.2 -p 4739 -l $FLOWDIR &
CAPD=$!

# Run probe first
./snabb ipfix probe -D $DURATION -a 10.0.0.1 -c 10.0.0.2\
  --active-timeout 5 --idle-timeout 5 -o tap $SNABB_PCI0 tap-snabb-ipfix &
sleep 0.5

# ... then feed it some packets
./snabb packetblaster replay -D $DURATION --no-loop $PCAP $SNABB_PCI1 > /dev/null

kill $CAPD

# Analyze with nfdump
DUMPFILE=`ls -1 $FLOWDIR | head -n 1`
nfdump -r $FLOWDIR/$DUMPFILE | grep "total flows: 6, total bytes: 24609, total packets: 43" > /dev/null
STATUS=$?

# teardown
ip link del tap-snabb-ipfix
rm -r $FLOWDIR

exit $STATUS
