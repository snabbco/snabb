#!/bin/bash
thisdir=$(dirname $0)
! "${thisdir}/../../env" pflua-pipelines-match --ir "${thisdir}/../data/wingolog.pcap" \
 "${thisdir}/opt-bug120-rangecheck-unopt.ir" "${thisdir}/opt-bug120-rangecheck-opt.ir" 13965 > /dev/null

"${thisdir}/../../env" pflua-pipelines-match --ir --opt-ir "${thisdir}/../data/wingolog.pcap" \
 "${thisdir}/opt-bug120-rangecheck-unopt.ir" 13965
