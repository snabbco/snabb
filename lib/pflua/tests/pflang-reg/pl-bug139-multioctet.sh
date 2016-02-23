#!/bin/bash
thisdir=$(dirname $0)
"${thisdir}/../../env" pflua-pipelines-match "${thisdir}/../data/wingolog.pcap" "ip[29:2] < 231" 16794
