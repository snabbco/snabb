#!/bin/bash

# Usage: cperf.sh plot <commit-range>
#        cperf.sh check <sha-x> <sha-y>
#
# In `plot' mode: Runs benchmarks for each merge commit in that range and
# records their results unless a record for that run already exists and
# plots the resulting records.
#
# In `check' mode: Compares benchmark results of commits <sha-x> and
# <sha-y> and prints the results.
#
# CPERFDIR must be an absolute path that designates a directory with a
# `benchmarks/' subdirectory containing the benchmark scripts to be run.

CPERFDIR=${CPERFDIR:-"/tmp/cperf"}

# Each benchmark script is called SAMPLESIZE times in order to calculate
# median values and standard deviation for their results.

SAMPLESIZE=${SAMPLESIZE:-"5"}



# Paths used by cperf:
benchmarks="$CPERFDIR/benchmarks" # Directory for benchmark scripts.
results="$CPERFDIR/results"       # Directory for data produced by cperf.
graph_data="$results/dat"         # Directory for results data.
graph_tmp="$results/tmp"          # Directory for temporary data.
graph="$results/benchmarks.png"   # Path to the resulting plot rendering.


# Run benchmark $1 SAMPLESIZE times and print median and standard
# deviation as two space separated columns.
function run_benchmark {

    # Run benchmark $1 SAMPLESIZE times and record results.
    results=$(
        for i in $(seq $SAMPLESIZE); do
            sh "$1"

            # If benchmark fails abort early.
            if [ "$?" != "0" ]; then
                return 1
            fi
        done
    )

    # Compute and print median and standard deciation for results.
    echo "$results" | \
        awk '{sum+=$1; sumsq+=$1*$1}
          END{print sum/NR,sqrt(sumsq/NR - (sum/NR)**2)}'
}

# Compile Gnuplot `plot' arguments for data files in data directory $1.
function compile_plot_args {
    for dat in "$1"/*; do
        echo -n "'$dat' \
using 0:2:3:xticlabels(1) \
with yerrorlines \
title '$(basename "$dat")', "
    done
}

# Gnuplot interface. Produce PNG plot for data files in $1 and write it
# to $2.
function plot {
    gnuplot <<EOF
set terminal png size 1600,800
set output "$2"
set offset graph 0.02, 0.2, 0.02, 0.02
#set yrange [0:50]
set ylabel "Mpps (mean of $SAMPLESIZE runs with standard deviation)"
set xlabel "Git ref (abbreviated)"
plot $(compile_plot_args "$1")
EOF
}

# Abbreviate rehash $1.
function shorthash {
    echo "${1:0:6}"
}

# Plot records for commits in $1.
function plot_records {

    # Ensure `graph_tmp' directory exists.
    mkdir -p "$graph_tmp"

    # Compile Gnuplot compatible data files.
    for refhash in $1; do
        for benchmark in "$graph_data/$refhash"/*; do
            echo "$(shorthash $refhash) $(cat $benchmark)" \
                >> "$graph_tmp/$(basename "$benchmark")"
        done
    done

    # Produce plot.
    plot "$graph_tmp" "$graph"

    # Delete temporary data.
    rm -rf $graph_tmp
}

# Plot mode: Plot benchmarking results for commit range `$1'.
function plot_mode {

    # Ensure `results' and `graph_data' directories exists.
    mkdir -p "$results" "$graph_data"

    # Get commits in <commit-range> ($1).
    commits="$(git log --format=format:%H --merges --reverse "$1")"

    # Traverse merge commits in <commit-range> ($1).
    for refhash in $commits; do

        # If record already exists, skip this refhash.
        if [ -d "$graph_data/$refhash" ]; then
            continue
        fi

        # Checkout refhash.
        git checkout $refhash

        # Rebuild.
        make

        # Ensure directory for record exists.
        mkdir -p "$graph_data/$refhash"

        # Run benchmarks and record their results in `graph_data'.
        for benchmark in "$benchmarks"/*; do

            # Try to run benchmark.
            result=$(run_benchmark "$benchmark")

            # Fall back to "0 0" if benchmark failed.
            if [ "$?" != "0" ]; then
                result="0 0"
            fi

            # Record results.
            echo "$result" \
                >> "$graph_data/$refhash/$(basename $benchmark)"

        done

    done

    # Return to master.
    git checkout master

    # Make a graph rendering.
    plot_records "$commits"
}

# Check mode: Compare benchmarking results of commit SHA-1 sums in `$@'.
function check_mode {

    # Print header.
    echo "Comparing with SAMPLESIZE=$SAMPLESIZE)"
    echo "(benchmark, mean score, standard deviation, abbrev. sha1 sum)"

    # Iterate over benchmarks.
    for benchmark in "$benchmarks"/*; do

        # Run benchmark for commits `$1' and `$2' and print results.
        echo # Seperarate benchmark results with a newline.
        for commit in $@; do

            # Checkout `commit'.
            git checkout "$commit" >/dev/null 2>&1

            # Rebuild.
            make >/dev/null 2>&1

            # Run benchmark.
            result=$(run_benchmark "$benchmark")
            if [ "$?" != "0" ]; then
                result="failed";
            fi

            # Print result.
            echo "$(basename "$benchmark") $result $(shorthash "$commit")"

        done

    done
}

# Decide which mode to run (`plot' or `check').
case $1 in
    plot)
        plot_mode "$2"
        ;;
    check)
        check_mode "$2" "$3"
        ;;
esac
