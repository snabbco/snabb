#!/usr/bin/env bash

# Script to generate Lua definitions of CPU Performance Monitoring
# Unit (PMU) events. These definitions can then be used as arguments
# to the Linux perf_event_open(2) system call to monitor detailed
# performance counters.
#
# Currently supports Intel CPUs and automatically downloads the latest
# definitions from an Intel website.
#
# This script is doing similar work to parts of Intel pmu-tools.

if [ ! -d download.01.org ]; then
    echo "Downloading Intel spec files" >&2
    wget -A csv,tsv,json -nv -r --no-parent https://download.01.org/perfmon/
fi
cd download.01.org/perfmon

echo "-- AUTOMATICALLY GENERATED FILE"
echo "-- Date: $(date)"
echo "-- Cmd:  $0 $@"
echo
echo "return"
echo " {"

tail -n +2 mapfile.csv | \
 while IFS=, read cpu version path type; do
    echo "  {\"$cpu\", \"$version\", \"$type\","
    echo "   {"
    tsv=$(echo $path | sed -e 's;^/;;' -e 's;json$;tsv;')
    echo "    -- source: $tsv"
    # Note: The intention is for values to be in the raw format
    # expected by Linux perf_event_open(2). However, the encoding in
    # this script may be incorrect for one or more event types.
    #
    # One reference is "perf list --help" section "RAW HARDWARE EVENT
    # DESCRIPTOR". This does not seem to say how to encode the offcore
    # events where two event codes are given in the spec file. More
    # research needed to understand what information this script needs
    # to include and how that should be passed to perf_event_open(2).
    grep -v '^ *#' $tsv | tail -n +2 | \
    case $type in
        core)
            awk -F '\t' \
                '{ printf("    [\"%s\"] = 0x%02x%02x,\n", tolower($3), $2, $1); }'
            ;;
        uncore)
            awk -F '\t' \
                '{ printf("    [\"%s\"] = 0x%02x%02x,\n", tolower($4), $3, $2); }'
            ;;
        offcore)
            echo "    -- [skipping offcore events. How are they encoded?]"
            ;;
    esac
    echo "   },"
    echo "  },"
 done
echo " }"
exit
