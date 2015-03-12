#!/bin/bash

# Usage: cperf.sh plot [<commit-range>]
#        cperf.sh check <sha-x> <sha-y>
#
# In `plot' mode: Runs benchmarks for each merge commit in that range and
# records their results unless a record for that run already exists and
# plots the resulting records. If commit-range is omitted the already
# persisted results are plotted instead.
#
# In `check' mode: Compares benchmark results of commits <sha-x> and
# <sha-y> and prints the results. Runs benchmarks for commits unless a
# record for that run already exists.
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


# Build SnabbSwitch at refhash ($1).
function checkout_and_build {
    git checkout "$1"
    git submodule update --init
    make
}

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
set ylabel "Score (mean of $SAMPLESIZE runs with standard deviation)"
set xlabel "Git ref (abbreviated)"
plot $(compile_plot_args "$1")
EOF
}

# Abbreviate rehash $1.
function shorthash {
    echo "${1:0:7}"
}

# Print path of persisted benchmark ($2) result for refhash ($1).
function persisted_path {
    echo "$graph_data/$1/$(basename $2)"
}

# Persist benchmark ($2) result ($3) for refhash ($1).
function persist_result {
    mkdir -p "$graph_data/$1"
    echo "$3" >> "$(persisted_path $1 $2)"
}

# Predicate to test if benchmark ($2) result for refhash ($1) is
# persisted.
function result_persisted_p {
    test -f "$(persisted_path $1 $2)"
}

# Print persisted benchmark ($2) result for refhash ($1).
function print_persisted_result {
    cat "$(persisted_path $1 $2)"
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

# Plot mode: Plot benchmarking results for commit range `$1'. If `$1' is
# omitted create plot for persisted results.
function plot_mode {

    if [ "$1" != "" ]; then

        # Get commits in <commit-range> ($1).
        commits="$(git log --format=format:%H --merges --reverse "$1")"

    else

        # Just use persisted results.
        commits="$(ls "$graph_data/")"

    fi

    # Run benchmarks and record their results in `graph_data'.
    for benchmark in "$benchmarks"/*; do

        # Traverse merge commits in <commit-range> ($1).
        for refhash in $commits; do

            # If record already exists, skip this refhash.
            if result_persisted_p "$refhash" "$benchmark"; then
                continue
            fi

            # Checkout refhash and rebuild.
            checkout_and_build $refhash

            # Try to run benchmark.
            result=$(run_benchmark "$benchmark")

            # Fall back to "0 0" if benchmark failed.
            if [ "$?" != "0" ]; then
                result="0 0"
            fi

            # Record results.
            persist_result "$refhash" "$benchmark" "$result"
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
    echo "Comparing with SAMPLESIZE=$SAMPLESIZE"
    echo "(benchmark, abbrev. sha1 sum, mean score, standard deviation)"

    # Iterate over benchmarks.
    for benchmark in "$benchmarks"/*; do

        # Run benchmark for commits `$1' and `$2' and print results.
        echo # Seperarate benchmark results with a newline.
        for commit in $@; do

            if result_persisted_p "$commit" "$benchmark"; then

                # Just use persisted result.
                result=$(print_persisted_result "$commit" "$benchmark")

            else

                # Checkout `commit' and rebuild.
                checkout_and_build "$commit" >/dev/null 2>&1

                # Run benchmark.
                result=$(run_benchmark "$benchmark")
                if [ "$?" != "0" ]; then
                    result="failed";
                else
                    # If successful persist result.
                    persist_result "$commit" "$benchmark" "$result"
                fi

            fi

            # Print result.
            echo "$(basename "$benchmark") $(shorthash "$commit") $result"

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
