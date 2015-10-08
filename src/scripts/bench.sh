#!/bin/bash

function n_times {
    for i in $(seq $1); do
        echo $(bench/$bench || echo "0")
    done
}

function median_stdev {
    awk '{sum+=$1; sumsq+=$1*$1}
          END{print sum/NR,sqrt(sumsq/NR - (sum/NR)**2)}'
}

for bench in $(ls bench/); do
    if [ -z "$SAMPLESIZE" ]; then
        echo $bench $(n_times 1 $bench) "-"
    else
        echo $bench $(n_times $SAMPLESIZE $bench | median_stdev)
    fi
done
