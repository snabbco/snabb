#!/bin/bash
thisdir=$(dirname $0)
"${thisdir}/../../env" pflua-pipelines-match "${thisdir}/../data/wingolog.pcap" "portrange 49577-19673" 938
