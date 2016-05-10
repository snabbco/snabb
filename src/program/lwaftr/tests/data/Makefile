VLAN_ID ?= 42

in_pcaps := $(filter-out empty.pcap,$(filter-out %-vlan.pcap,$(wildcard *.pcap)))
out_pcaps := $(patsubst %.pcap,%-vlan.pcap,$(in_pcaps))

%-vlan.pcap: %.pcap
	python2 add-dot1q.py $< $@ $(VLAN_ID)

all: $(out_pcaps)

clean:
	$(RM) $(out_pcaps)
