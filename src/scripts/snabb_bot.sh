#!/bin/bash

# Snabb Switch CI for GitHub Pull Requests. Depends on `jq'
# (http://stedolan.github.io/jq/).

export SNABBBOTDIR=${SNABBBOTDIR:-"/tmp/snabb_bot"}
export REPO=${REPO:-"SnabbCo/snabbswitch"}
export JQ=${JQ:-$(which jq)}
export SNABB_TEST_IMAGE=${SNABB_TEST_IMAGE:=eugeneia/snabb-nfv-test}
export CONTEXT=${CONTEXT:-"$(hostname)-$SNABB_TEST_IMAGE"}
cpu=$(grep 'model name' /proc/cpuinfo | head -n1 | cut -d ':' -f 2)
export INFO=${INFO:-"$(uname -n -s -r -m)$cpu / $SNABB_TEST_IMAGE"}


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
    mkdir -p "$SNABBBOTDIR" "$logdir" "$tmpdir"
}

function clean { rm -rf "$tmpdir"; }

function fetch_pull_requests {
    curl "https://api.github.com/repos/$REPO/pulls" > "$tmpdir/pulls"
}

function pull_request_ids { "$JQ" ".[].number" "$tmpdir/pulls"; }

function pull_request_by_id {
    "$JQ" "map(select(.number == $1))[0]" "$tmpdir/pulls"
}

function pull_request_head {
    echo "$(pull_request_by_id $1)" | "$JQ" -r ".head.sha"
}

function pull_request_base {
    echo "$(pull_request_by_id $1)" | "$JQ" -r ".base.sha"
}

function pull_request_repo {
    echo "$(pull_request_by_id $1)" | "$JQ" -r ".head.repo.clone_url"
}

function pull_request_log { echo "$logdir/$(pull_request_head $id)"; }

function pull_request_new_p {
    test ! -f "$logdir/$(pull_request_head $1)"
}

function repo_path { echo "$tmpdir/repo"; }

function clone_pull_request_repo {
    rm -rf $(repo_path)
    git clone $(pull_request_repo $1) $(repo_path)
}

function build1 {
    git checkout $1 && git submodule update --init && make
}

function build {
    out=$(build1 $1 2>&1)
    if [ "$?" != 0 ]; then
        echo "ERROR: Failed to build $1"
        echo "$out"
        echo
        return 1
    fi
}

function log_status {
    if grep "ERROR" $(pull_request_log $1) 2>&1 >/dev/null; then
        echo "failure"
    else
        echo "success"
    fi
}

function log_header {
    echo Node / Image: $INFO
    echo PR / Head: \#$1 / $(pull_request_head $id)
    echo
}

function dock_make { (cd src/; scripts/dock.sh make $1); }

function check_for_performance_regressions { base=$1; head=$2
    echo "Checking for performance regressions:"
    build $base || return
    dock_make benchmarks > $tmpdir/base_benchmarks
    build $head || return
    dock_make benchmarks > $tmpdir/head_benchmarks
    for bench in $(cut -d " " -f 1 $tmpdir/head_benchmarks); do
        if grep $bench $tmpdir/base_benchmarks 2>&1 >/dev/null; then
            echo $(grep $bench $tmpdir/base_benchmarks) \
                 $(grep $bench $tmpdir/head_benchmarks) \
                | awk '
BEGIN {
    minratio = 0.85;
}

{ if ($2+0 != 0) { ratio = $4 / $2; } else { ratio = $4; }
  if (ratio < minratio) {
      print "ERROR", $1, "->", ratio, "of", $2;
  } else {
      print "BENCH",    $1, "->", ratio, "of", $2;
  }
}
'
        fi
    done
    echo
}

function check_test_suite { head=$1
    echo "Checking test suite:"
    build $head || return
    if ! dock_make test_ci; then
        for log in src/testlog/*; do
            echo $log:
            cat $log
            echo
        done
    fi
    echo
}

function post_gist {
    # Create API request body for Gist API.
    cat "$1" \
        | "$JQ" -s -R "{public: true, files: {log: {content: .}}}" \
        > "$tmpdir/request"
    # Create Gist.
    curl -X POST \
        -u "$GITHUB_CREDENTIALS" \
        -d @"$tmpdir/request" \
        "https://api.github.com/gists" \
        | "$JQ" .html_url
}

function post_status { id=$1; status=$2; gist=$3
    # Create API request body for status API.
    cat > "$tmpdir/request" \
        <<EOF
{"context": "$CONTEXT",
 "description": "$INFO",
 "state": "$status",
 "target_url": $www_log }
EOF
    # POST status.
    curl -X POST -u "$GITHUB_CREDENTIALS" -d @"$tmpdir/request" \
        "https://api.github.com/repos/$REPO/statuses/$(pull_request_head $id)" \
        > /dev/null
}


init
fetch_pull_requests || exit 1
for id in $(pull_request_ids); do
    (pull_request_new_p $id && clone_pull_request_repo $id) || continue
    (cd $(repo_path)
        log_header $id
        check_for_performance_regressions $(pull_request_base $id) $(pull_request_head $id)
        check_test_suite $(pull_request_head $id)) \
            2>&1 > $(pull_request_log $id)
    [ ! -z "$GITHUB_CREDENTIALS" ] || continue
    post_status $id $(log_status $id) $(post_gist $(pull_request_log $id))
done
clean
