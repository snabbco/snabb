TOP_SRCDIR:=..
include $(TOP_SRCDIR)/common.mk

all:

clean:
	rm -f tmp.pcap

# Very lightweight tests, to avoid low-hanging tool breakage
# during internal API changes
# TODO: add pflua-pipeline-match IR checks
tools_run:
	./pflua-pipelines-match ../tests/data/arp.pcap "arp" 1
	./pflua-pipelines-match -O0 ../tests/data/arp.pcap "arp" 1
	./pflua-pipelines-match --force-opt ../tests/data/arp.pcap "arp" 1

check: tools_run
	./pflua-filter ../tests/data/v4.pcap ./tmp.pcap "ip"
	cmp ../tests/data/v4.pcap tmp.pcap
	rm tmp.pcap
