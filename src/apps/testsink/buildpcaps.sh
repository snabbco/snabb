echo 'wrpcap("selftest1.pcap", [ Ether()/Dot1Q(vlan=x)/IP(src="127.0.0.1")/UDP(sport=10)/Raw(open("/dev/urandom","rb").read(0)) for x in range(5,70) ])' | scapy
echo 'wrpcap("selftest2.pcap", [ Ether()/Dot1Q(vlan=x)/IP(src="127.0.0.1")/UDP(sport=10)/Raw(open("/dev/urandom","rb").read(0)) for x in range(5,70) if x % 2 == 0 ])' | scapy
