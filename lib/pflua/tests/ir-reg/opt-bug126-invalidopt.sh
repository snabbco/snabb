#!/bin/bash
thisdir=$(dirname $0)
! "${thisdir}/../../env" pflua-pipelines-match --ir "${thisdir}/../data/wingolog.pcap" \
 "${thisdir}/opt-bug126-unopt.ir" "${thisdir}/opt-bug126-opt.ir" 13965 > /dev/null

"${thisdir}/../../env" pflua-pipelines-match --ir --opt-ir "${thisdir}/../data/wingolog.pcap" "${thisdir}/opt-bug126-unopt.ir" 13965
