#!/bin/bash

# Neutron synchronization master process to run on the Network Node.

function error()
{
    # $1: error message
    echo "ERROR: $1"
    exit 1
}

function check_env_vars()
{
    [ ! -z "$DB_USER" ] || error "check_env_vars: \$DB_USER not set"
    [ ! -z "$DB_PASSWORD" ] || error "check_env_vars: \$DB_PASSWORD not set"
    [ ! -z "$DB_DUMP_PATH" ] || error "check_env_vars: \$DB_DUMP_PATH not set"
    [ ! -z "$DB_HOST" ] || export DB_HOST=localhost
    [ ! -z "$DB_PORT" ] || export DB_PORT=3306
    [ ! -z "$DB_NEUTRON" ] || export DB_NEUTRON=neutron_ml2
    [ ! -z "$DB_NEUTRON_TABLES" ] || export DB_NEUTRON_TABLES="networks \
        ports ml2_network_segments securitygroups securitygrouprules \
        securitygroupportbindings"
    [ ! -z "$SYNC_LISTEN_HOST" ] || export SYNC_LISTEN_HOST=127.0.0.1
    [ ! -z "$SYNC_LISTEN_PORT" ] || export SYNC_LISTEN_PORT=9418
    [ ! -z "$SYNC_INTERVAL" ] || export SYNC_INTERVAL=1
}

function check_deps()
{
    (which git > /dev/null) || error "missing dependency: git"
    (which mysqldump > /dev/null) || error "missing dependency: mysqldump"
}

function log { echo "[$(date +"%F %T %Z")]" "$1"; }

function run()
{
    cd "$DB_DUMP_PATH"
    [ -f /tmp/neutron-sync-master.pid ] && kill $(cat /tmp/neutron-sync-master.pid)
    export GIT_AUTHOR_NAME="Snabb NFV sync master"
    export GIT_AUTHOR_EMAIL="snabbnfv-sync-master"
    export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
    export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
    log "Starting Git daemon"
    git daemon --reuseaddr --listen="$SYNC_LISTEN_HOST" \
        --port="$SYNC_LISTEN_PORT" --base-path="$DB_DUMP_PATH/.." --export-all \
        --verbose --pid-file=/tmp/neutron-sync-master.pid --detach "$DB_DUMP_PATH" \
        >/dev/null 2>&1
    while true
    do
        mysqldump -n -y -q -u${DB_USER} -p${DB_PASSWORD} -h ${DB_HOST} \
            -P ${DB_PORT} -T ${DB_DUMP_PATH} --skip-dump-date \
            ${DB_NEUTRON} ${DB_NEUTRON_TABLES}
        git add *.txt *.sql >/dev/null 2>&1
        if ! git diff --quiet --cached; then
            log "Pushing configuration changes."
            if [ $initial = true ]; then
                git commit -m "Configuration update" >/dev/null
                initial=false
            else
                git commit --amend -m "Configuration update" >/dev/null
                git reflog expire --expire-unreachable=0 --all >/dev/null
                git prune --expire 0 >/dev/null
            fi
        fi
        sleep "$SYNC_INTERVAL"
        #check that the daemon is still running
        GITPID=$(cat /tmp/neutron-sync-master.pid)
        if ! ps -p $GITPID > /dev/null
        then
            error "git daemon with $GITPID is down"
        fi
    done
}

## MAIN ##

echo "DBG: MAIN: starting"

check_env_vars
check_deps

echo "DBG: \$DB_DUMP_PATH = $DB_DUMP_PATH"

[ -d "$DB_DUMP_PATH" ] ||  mkdir -p "$DB_DUMP_PATH" || error 'MAIN: cannot make repo dir'
[ -d "$DB_DUMP_PATH/.git" ] || git init "$DB_DUMP_PATH" || error 'MAIN: error initializing repo'

#sudo chmod 777 "$DB_DUMP_PATH"
initial=true
run "$DB_DUMP_PATH"

