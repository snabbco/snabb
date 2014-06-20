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

    # Unless log for $pull exists...
    if [ ! -f "$logdir/$number" ]; then

        # Clone and checkout HEAD.
        repo="$(echo "$pull" | "$JQ" -r ".head.repo.clone_url")"
        head="$(echo "$pull" | "$JQ" -r ".head.sha")"
        base="$(echo "$pull" | "$JQ" -r ".base.sha")"
        git clone "$repo" "$tmpdir/repo" \
            || continue
        (
            cd "$tmpdir/repo"
            git checkout "$head"

            # Build.
            git submodule update --init > /dev/null 2>&1
            make > /dev/null 2>&1
            
            # If buid was successful run tasks.
            if [ "$?" = "0" ]; then

                echo "Running integration tasks for ${head:0:7} on \`$(hostname)\`:" \
                    >> "$logdir/$number"
                for task in "$tasksdir"/*; do
                    printf "\n\`$task\`\n\n" >> "$logdir/$number"
                    out=$("$task" "$base" "$head" 2>&1)
                    if [ "$?" = "0" ]; then
                        echo "$out" >> "$logdir/$number"
                    else
                        echo "\`$task\` failed." >> "$logdir/$number"
                    fi
                done
                # Blank line.
                echo >> "$logdir/$number"

            else

                echo "Build failed." >> "$logdir/$number"

            fi
        )
        # Delete cloned repository.
        rm -rf  "$tmpdir/repo"

        # Add comment (if we got credentials).
        if [ ! "$GITHUB_CREDENTIALS" = "" ]; then
            # Create API request body.
            cat "$logdir/$number" \
                |"$JQ" -s -R "{body: .}" \
                > "$tmpdir/request"

            # POST it to GitHub
            curl \
            -X POST \
            -u "$GITHUB_CREDENTIALS" \
            -d @"$tmpdir/request" \
            "https://api.github.com/repos/$REPO/issues/$number/comments"
        fi

    fi

done

# Delete `tmpdir'.
rm -rf "$tmpdir"
