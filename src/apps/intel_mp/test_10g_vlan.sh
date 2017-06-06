#!/usr/bin/env bash
#
# Test VMDq mode with vlan tagging

./testvlan.snabb $SNABB_PCI_INTEL0 $SNABB_PCI_INTEL1 "90:72:82:78:c9:7a" source-vlan.pcap
