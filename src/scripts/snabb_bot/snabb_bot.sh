#!/bin/bash

# Perform `tasks' for GitHub pull requests and add their output as
# comments. Depends on `jq' (http://stedolan.github.io/jq/).

SNABBBOTDIR=${SNABBBOTDIR:-"/tmp/snabb_bot"}
JQ=${JQ:-$(which jq)}

# Paths used by `snabb_bot.sh'.
logdir="$SNABBBOTDIR/log"
tasksdir="$SNABBBOTDIR/tasks"
tmpdir="$SNABBBOTDIR/tmp"

if [ "$REPO" = "" ]; then
    echo "Error: Enviromnent variable REPO is not set."
    echo "Set it to 'SnabbCo/snabbswitch' for instance."
    exit 1
fi

if [ ! -x "$JQ" ]; then
    echo "Error: 'jq' could not be found."
    echo "Please set the environment variable JQ to the path of the"
    echo "'jq' executable."
    exit 1
fi

if [ "$GITHUB_CREDENTIALS" = "" ]; then
    echo "Warning: Environment variable GITHUB_CREDENTIALS is not set."
    echo "'$0' will not be able to post comments to pull requests."
fi

# Ensure paths exists.
mkdir -p "$SNABBBOTDIR" "$logdir" "$tasksdir" "$tmpdir"

# Fetch current list of pull requests.
curl "https://api.github.com/repos/$REPO/pulls" > "$tmpdir/pulls" \
    || exit 1

# Iterate over pull requests.
for number in $("$JQ" ".[].number" "$tmpdir/pulls"); do
    pull=$("$JQ" "map(select(.number == $number))[0]" "$tmpdir/pulls")

    # `status' is success unless something goes wrong.
    status=success

    head="$(echo "$pull" | "$JQ" -r ".head.sha")"
    log="$logdir/$head"

    # Unless log for $pull exists...
    if [ ! -f "$log" ]; then

        # Clone repo.
        repo="$(echo "$pull" | "$JQ" -r ".head.repo.clone_url")"
        base="$(echo "$pull" | "$JQ" -r ".base.sha")"
        git clone "$repo" "$tmpdir/repo" \
            || continue

        # Prepare submodules.
        (cd "$tmpdir/repo"
            git submodule update --init > /dev/null 2>&1)
            
        # If buid was successful run tasks.
        if [ "$?" = "0" ]; then

            echo "Running integration tasks for ${head:0:7} on $(hostname):" \
                >> "$log"
            for task in "$tasksdir"/*; do
                printf "\n$task" >> "$log"

                # Ensure `head' is checked out and (re)built.
                (cd "$tmpdir/repo"
                    git checkout "$head"
                    make > /dev/null 2>&1)

                # Run task and record results.
                out=$( (cd "$tmpdir/repo"
                        "$task" "$base" "$head" 2>&1) )
                if [ "$?" != "0" ]; then
                    echo ": failed" >> "$log"
                    status=failure
                else
                    echo ": success" >> "$log"
                fi

                # Print task output to `log'.
                echo "$out" >> "$log"
            done

            # Blank line to seperate task output.
            echo >> "$log"

        else

            # Fail on build error.
            echo "Build failed." >> "$log"
            status=failure

        fi

        # Delete cloned repository.
        rm -rf  "$tmpdir/repo"

        # Post gist and set status (if we got credentials).
        if [ ! "$GITHUB_CREDENTIALS" = "" ]; then

            # Create API request body for Gist API.
            cat "$log" \
                | "$JQ" -s -R "{public: true, files: {log: {content: .}}}" \
                > "$tmpdir/request"

            # Create Gist.
            www_log=$(curl -X POST \
                -u "$GITHUB_CREDENTIALS" \
                -d @"$tmpdir/request" \
                "https://api.github.com/gists" \
                | "$JQ" .html_url)

            # Create API request body for status API.
            cat > "$tmpdir/request" \
                <<EOF
{"context": "snabb_bot",
 "description": "SnabbBot",
 "state": "$status",
 "target_url": $www_log }
EOF

            # POST status.
            curl \
                -X POST \
                -u "$GITHUB_CREDENTIALS" \
                -d @"$tmpdir/request" \
                "https://api.github.com/repos/$REPO/statuses/$head" \
                > /dev/null

        fi

    fi

done

# Delete `tmpdir'.
rm -rf "$tmpdir"
