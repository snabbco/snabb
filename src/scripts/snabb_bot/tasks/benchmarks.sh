#!/bin/bash

# Run benchmarks. This task requires the `CPERF' and `CPERFDIR'
# environment variables to be set. `CPERF' must point to `cperf.sh'.

set -e

"$CPERF" check "$1" "$2" | awk '
BEGIN {
    minratio = 0.85;
}

{ if (NR > 3 && ((NR - 1) % 3) == 0) {
        bench = $1;
        score = $3;
    }
}

{ if (NR > 3 && ((NR - 2) % 3) == 0) {
        ratio = $3 / score;
        if (ratio < minratio) {
            print "REGRESSION:", bench, "on", $2, ":", ratio, "of", score;
            exit 1;
        } else {
            print "OK:", bench, "on", $2, ":", ratio, "of", score;
        }
    }
}
'
