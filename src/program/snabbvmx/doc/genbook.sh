#!/usr/bin/env bash

# This shell scripts generates the top-level Markdown structure of the
# Snabb lwAFTR manual.
#
# The authors list is automatically generated from Git history,
# ordered from most to least commits.

# Script based on src/doc/genbook.sh

cat <<EOF
% SnabbVMX Manual

---

% Version $(git log -n1 --format="format:%h, %ad%n")

$(cat README.md)

$(cat README.install.md)

$(cat README.configuration.md)

$(cat README.userguide.md)

$(cat README.troubleshooting.md)

EOF
