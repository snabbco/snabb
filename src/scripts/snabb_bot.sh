#!/usr/bin/env bash

# Snabb CI for GitHub Pull Requests. Depends on `jq'
# (http://stedolan.github.io/jq/).

export SNABBBOTDIR=${SNABBBOTDIR:-"/tmp/snabb_bot"}
export REPO=${REPO:-"snabbco/snabb"}
export JQ=${JQ:-$(which jq)}
export SNABB_TEST_IMAGE=${SNABB_TEST_IMAGE:-eugeneia/snabb-nfv-test}
export CONTEXT=${CONTEXT:-"$(hostname)-$SNABB_TEST_IMAGE"}
machine="$(uname -n -s -r -m) $(grep 'model name' /proc/cpuinfo | head -n1 | cut -d ':' -f 2)"
export INFO=${INFO:-"$machine / $SNABB_TEST_IMAGE"}
export SNABB_PERF_SAMPLESIZE=${SNABB_PERF_SAMPLESIZE:-5} # For scripts/bench.sh


function init {
    if [ ! -x "$JQ" ]; then
        echo "Error: 'jq' could not be found."
        echo "Please set the environment variable JQ to the path of the"
        echo "'jq' executable."
        exit 1
    fi
    if [ "$GITHUB_CREDENTIALS" = "" ]; then
        echo "Warning: Environment variable GITHUB_CREDENTIALS is not set."
        echo "$0 will not be able to post comments to pull requests."
    fi
    export logdir="$SNABBBOTDIR/log"
    export tmpdir="$SNABBBOTDIR/tmp"
    rm -rf "$tmpdir"
    mkdir -p "$SNABBBOTDIR" "$logdir" "$tmpdir"
}

function fetch_pull_requests {
    local url="https://api.github.com/repos/$REPO/pulls?per_page=100"
    if [[ -n "$CLIENT_ID" && -n "$CLIENT_SECRET" ]]; then
        url="$url?client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}"
    fi
    curl -u "$GITHUB_CREDENTIALS" "$url" > "$tmpdir/pulls"
}

function pull_request_ids { "$JQ" ".[].number" "$tmpdir/pulls"; }

function pull_request_by_id {
    "$JQ" "map(select(.number == $1))[0]" "$tmpdir/pulls"
}

function pull_request_head {
    echo "$(pull_request_by_id $1)" | "$JQ" -r ".head.sha"
}

function pull_request_target {
    echo "$(pull_request_by_id $1)" | "$JQ" -r ".base.ref"
}

function repo_path { echo "$tmpdir/repo"; }

function target_head {
    (cd $(repo_path) && git rev-parse --verify $(pull_request_target $1))
}

function ensure_target_fetched {
    (cd $(repo_path) && \
        (git rev-parse --verify $1 >/dev/null 2>&1 || git fetch origin $1:$1))
}

function pull_request_log {
    echo "$logdir/$(target_head $1)+$(pull_request_head $1)"
}

function pull_request_new_p {
    test ! -f "$(pull_request_log $1)"
}

function clone_upstream {
    local url="https://github.com/$REPO.git"
    if [[ -n "$GITHUB_CREDENTIALS" ]]; then
        url="https://$GITHUB_CREDENTIALS@github.com/$REPO.git"
    fi
    git clone $url $(repo_path) \
        && (cd $(repo_path)
               git config user.email "snabb_bot.service@$(hostname)"
               git config user.name "Snabb Bot")
}

function build { (cd src && scripts/dock.sh "(cd .. && make)"); }

function log_status {
    if grep "ERROR" $(pull_request_log $1) >/dev/null 2>&1; then
        echo "failure"
    else
        echo "success"
    fi
}

function pci_info { var=$1; value=$2
    [ -z  "$2" ] || echo $1=$(lspci -D | grep $2)
}

function log_header {
    echo Host: $machine
    echo Image: $SNABB_TEST_IMAGE
    echo Pull Request: \#$1
    echo Target Head: $(target_head $1)
    echo Pull Request Head: $(pull_request_head $1)
    pci_info SNABB_PCI0 $SNABB_PCI0
    pci_info SNABB_PCI1 $SNABB_PCI1
    pci_info SNABB_PCI_INTEL0 $SNABB_PCI_INTEL0
    pci_info SNABB_PCI_INTEL1 $SNABB_PCI_INTEL1
    pci_info SNABB_PCI_INTEL1G0 $SNABB_PCI_INTEL1G0
    pci_info SNABB_PCI_INTEL1G1 $SNABB_PCI_INTEL1G1
    pci_info SNABB_PCI_SOLARFLARE0 $SNABB_PCI_SOLARFLARE0
    pci_info SNABB_PCI_SOLARFLARE1 $SNABB_PCI_SOLARFLARE1
    echo
}

function benchmark_results { echo $tmpdir/$1_benchmarks; }

function benchmark_target1 {
    git clean -f -f \
        && git checkout --force $(target_head $1) \
        && build \
        && dock_make benchmarks > $(benchmark_results $(pull_request_target $1))
}
function benchmark_target { benchmark_target1 $1 >/dev/null 2>&1; }

function merge_pr_with_target1 {
    git clean -f -f \
        && git fetch origin pull/$1/head:pr$1 \
        && git checkout --force pr$1 \
        && git merge $(target_head $1) \
        && build
}
function merge_pr_with_target {
    out=$(merge_pr_with_target1 $1 2>&1)
    if [ "$?" != 0 ]; then
        echo "ERROR: Failed to build $1"
        echo "$out"
        git status
        echo
        return 1
    fi
}

function dock_make {
    (cd src/; timeout --foreground 1h scripts/dock.sh make $1);
}

function check_for_performance_regressions {
    echo "Checking for performance regressions:"
    dock_make benchmarks > $(benchmark_results pr)
    for bench in $(cut -d " " -f 1 $(benchmark_results pr)); do
        if grep "$bench " $(benchmark_results $1) >/dev/null 2>&1; then
            echo $(grep "$bench " $(benchmark_results $1)) \
                 $(grep "$bench " $(benchmark_results pr)) \
                | awk '
BEGIN {
    minratio = 0.85;
}

{ if ($2+0 != 0) { ratio = $5 / $2; } else { ratio = $5; }
  if ((ratio < minratio) && ($2+0 != 0)) {
      print "ERROR", $1, "->", ratio, "of", $2, "(SD:", $3, ")";
  } else {
      print "BENCH", $1, "->", ratio, "of", $2, "(SD:", $3, ")";
  }
}
'
        fi
    done
    echo
}

function check_test_suite {
    echo "Checking test suite:"
    dock_make test | tee make-test.log
    echo
    echo "Errors during tests:"
    for log in $(grep ERROR make-test.log | awk '{print $2}'); do
        echo $log:
        cat src/$log
        echo
    done
    echo
}

function post_gist {
    local url="https://api.github.com/gists"
    if [[ -n "$CLIENT_ID" && -n "$CLIENT_SECRET" ]]; then
        url="$url?client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}"
    fi
    # Create API request body for Gist API.
    cat "$1" \
        | "$JQ" -s -R "{public: true, files: {log: {content: .}}}" \
        > "$tmpdir/request"
    # Create Gist.
    curl -X POST \
        -u "$GITHUB_CREDENTIALS" \
        -d @"$tmpdir/request" \
        "$url" \
        | "$JQ" .html_url
}

function post_status { id=$1; status=$2; gist=$3
    local url="https://api.github.com/repos/$REPO/statuses/$(pull_request_head $id)"
    if [[ -n "$CLIENT_ID" && -n "$CLIENT_SECRET" ]]; then
        url="$url?client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}"
    fi
    # Create API request body for status API.
    cat > "$tmpdir/request" \
        <<EOF
{"context": "$CONTEXT",
 "description": "$INFO",
 "state": "$status",
 "target_url": $gist }
EOF
    # POST status.
    curl -X POST -u "$GITHUB_CREDENTIALS" -d @"$tmpdir/request" \
        "$url" \
        > /dev/null
}


init
fetch_pull_requests && clone_upstream || exit 1
for id in $(pull_request_ids); do
    ensure_target_fetched $(pull_request_target $id) \
        && pull_request_new_p $id \
        || continue
    (cd $(repo_path)
        [ -f $(benchmark_results $(pull_request_target $id)) ] \
            || benchmark_target $id
        log_header $id
        if merge_pr_with_target $id; then
            check_for_performance_regressions $(pull_request_target $id)
            check_test_suite
        fi) 2>&1 > $(pull_request_log $id)
    [ ! -z "$GITHUB_CREDENTIALS" ] || continue
    post_status $id $(log_status $id) $(post_gist $(pull_request_log $id))
done
