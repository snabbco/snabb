#!/usr/bin/env bash

# This shell scripts generates the top-level Markdown structure of the
# Snabb lwAFTR manual.
#
# The authors list is automatically generated from Git history,
# ordered from most to least commits.

# Script based on src/doc/genbook.sh

lwaftr_app=../

cat <<EOF
% Snabb lwAFTR Manual
% $(git log --pretty="%an" $lwaftr_app | \
        grep -v -e '^root$' | \
        sort | uniq -c | sort -nr | sed 's/^[0-9 ]*//' | \
        awk 'BEGIN     { first=1; }
             (NF >= 2) { if (first) { first=0 } else { printf("; ") };
                         printf("%s", $0) }
             END { print("") }')
% Version $(git log -n1 --format="format:%h, %ad%n")

$(cat README.md)

$(cat README.running.md)

$(cat README.bindingtable.md)

$(cat README.configuration.md)

$(cat README.benchmarking.md)

$(cat README.performance.md)

$(cat README.virtualization.md)

$(cat README.rfccompliance.md)

$(cat README.troubleshooting.md)

$(cat README.counters.md)

$(cat README.breaking_changes.md)

EOF
