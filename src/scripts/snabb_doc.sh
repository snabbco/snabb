#!/usr/bin/env bash

# Snabb Doctor: continuously publish Snabb manual as single HTML file for tags,
# master and GitHub Pull Requests using GitHub pages. Depends on `jq'
# (http://stedolan.github.io/jq/).

export SNABBDOCDIR=${SNABBDOCDIR:-"/tmp/snabb_doc"}
export REPO=${REPO:-"snabbco/snabb"}
export DOCREPO=${DOCREPO:-"snabbco/snabbco.github.io"}
export DOCURL=${DOCURL:-"https://snabbco.github.io"}
export JQ=${JQ:-$(which jq)}

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
    export logdir="$SNABBDOCDIR/log"
    export tmpdir="$SNABBDOCDIR/tmp"
    export docdir="$SNABBDOCDIR/pages"
    mkdir -p "$SNABBDOCDIR" "$logdir" "$tmpdir"
}

function clean { rm -rf "$tmpdir"; }

function fetch_pull_requests {
    curl "https://api.github.com/repos/$REPO/pulls?per_page=100" \
        > "$tmpdir/pulls"
}

function pull_request_ids { "$JQ" ".[].number" "$tmpdir/pulls"; }

function pull_request_by_id {
    "$JQ" "map(select(.number == $1))[0]" "$tmpdir/pulls"
}

function pull_request_head {
    echo "$(pull_request_by_id $1)" | "$JQ" -r ".head.sha"
}

function repo_path { echo "$tmpdir/repo"; }

function current_tag {
    (cd $(repo_path) && git tag --points-at $(git log --format=%H -n1))
}

function clone_upstream {
    git clone https://github.com/$REPO.git $(repo_path)
}

function fetch_pr_head {
    (cd $(repo_path) && git fetch origin pull/$1/head:pr$1)
}

function ensure_docs_cloned {
    [ -d $docdir ] || \
        git clone https://$GITHUB_CREDENTIALS@github.com/$DOCREPO.git $docdir \
            && (cd $docdir
                   git config user.email "snabb_doc.service@$(hostname)"
                   git config user.name "Snabb Doc")
    mkdir -p $docdir/{sha1,tag}
}

function push_new {
    (cd $docdir && \
        git add -A && git commit -m "$1" && git push -u origin master)
}

function sha1_url  { echo $DOCURL/sha1/$1.html; }
function sha1_out  { echo $docdir/sha1/$1.html; }
function tag_out   { echo $docdir/tag/$1.html;  }
function index_out { echo $docdir/index.html;   }

function build_doc1 {
    ((cd $(repo_path)/src && git checkout $1 && make doc/snabbswitch.html) \
        && mv $(repo_path)/src/doc/snabbswitch.html $2) \
 || ((cd $(repo_path)/src && git checkout $1 && make obj/doc/snabbswitch.html) \
        && mv $(repo_path)/src/obj/doc/snabbswitch.html $2) \
 || ((cd $(repo_path)/src && git checkout $1 && make obj/doc/snabb.html) \
        && mv $(repo_path)/src/obj/doc/snabb.html $2)
}

function build_doc {
    (cd $(repo_path) && make clean)
    out=$(build_doc1 $1 $2 2>&1)
    if [ "$?" != 0 ]; then
        echo "$out" > $2
        return 1
    fi
}

function gh_status {
    if [ $status = 0 ]; then echo success
    else                     echo failure; fi
}

function post_status { id=$1; status=$2; url=$3
    # Create API request body for status API.
    cat > "$tmpdir/request" \
        <<EOF
{"context": "SnabbDoc",
 "description": "Documentation as single HTML file",
 "state": "$status",
 "target_url": "$url" }
EOF
    # POST status.
    curl -X POST -u "$GITHUB_CREDENTIALS" -d @"$tmpdir/request" \
        "https://api.github.com/repos/$REPO/statuses/$(pull_request_head $id)" \
        > /dev/null
}

init
ensure_docs_cloned || exit 1
fetch_pull_requests && clone_upstream || exit 1

# Build manual for current tag(s) unless it already exists
for tag in $(current_tag); do
    if [ ! -f $(tag_out $tag) ]; then
        build_doc $tag $(tag_out $tag) \
            && cp $(tag_out $tag) $(index_out)
    fi
done

# Build manual for open PRs and link it as status
for id in $(pull_request_ids); do
    [ -f $(sha1_out $(pull_request_head $id)) ] && continue
    fetch_pr_head $id || continue
    build_doc $(pull_request_head $id) $(sha1_out $(pull_request_head $id))
    status=$?
    [ -z "$GITHUB_CREDENTIALS" ] && continue
    post_status $id $(gh_status $status) $(sha1_url $(pull_request_head $id))
done

push_new update
clean
