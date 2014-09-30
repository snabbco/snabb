#
# This test plan keeps the focus on regression testing. Please, add new test
# cases to cover new code and keep the old test cases working
#
# Those test cases are a minimum set. They should run fast and pass
#
# Set 'enabled' to 'false' in order to skip test cases while hacking
#
# Use "make test | grep 'tc id'" to identify test cases failing quickly
#
# i.e:
#  $ make test | grep 'tc id'
#  tc id 1 FAIL (48 != 47)
#  tc id 2 PASS
#  tc id 3 SKIP
#  ...
#

id:1
description:baseline
filter:
pcap_file:ws/v4.pcap
expected_result:43
enabled:true

id:2
description:ip
filter:ip
pcap_file:ws/v4.pcap
expected_result:43
enabled:true

id:3
description:tcp
filter:tcp
pcap_file:ws/v4.pcap
expected_result:41
enabled:true

id:4
description:tcp port
filter:tcp port 80
pcap_file:ws/v4.pcap
expected_result:41
enabled:true

id:5
description:tcp dst port
filter:tcp dst port 23
pcap_file:ws/telnet-cooked.pcap
expected_result:48
enabled:true

id:6
description:udp dst port
filter:udp dst port 2087
pcap_file:ws/tftp_wrq.pcap
expected_result:49
enabled:true

id:7
description:host check
filter:host 192.168.0.13
pcap_file:ws/tftp_wrq.pcap
expected_result:100
enabled:true

id:8
description:net mask test success
filter:net 192.168.0.0 mask 255.255.255.0
pcap_file:ws/telnet-cooked.pcap
expected_result:92
enabled:true

id:9
description:net mask test failure
filter:net 192.168.50.0 mask 255.255.255.0
pcap_file:ws/telnet-cooked.pcap
expected_result:0
enabled:true

id:10
description:no packets
filter:icmp
pcap_file:igalia/empty.pcap
expected_result:0
enabled:true

id:11
description:no packets
filter:tcp port 80 and (((ip[2:2] - ((ip[0]&0xf)<<2)) - ((tcp[12]&0xf0)>>2)) != 0)
pcap_file:igalia/empty.pcap
expected_result:0
enabled:true
