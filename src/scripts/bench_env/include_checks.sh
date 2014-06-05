
import_env () {
    # Check if configuration file is present on etc directory
    ENV_FILE="$1/bench_conf.sh"
    [ -f $ENV_FILE ] && . $ENV_FILE || \
    {
        printf "Configuration file $ENV_FILE not found.\n" && \
        return 1
    }

    printf "Sourced $ENV_FILE\n"
    printf "\n------\n"
    cat $ENV_FILE
    printf "\n------\n"
    return 0
}

wait_pid () {
    for pid in "$@"; do
        wait $pid
    done
}

kill_pid () {
    for pid in "$@"; do
        kill -9 $pid > /dev/null 2>&1 || true
    done
}

rm_file () {
    for f in "$@"; do
        [ -f "$f" ] && rm $f
    done
}

on_exit () {
    # cleanup on exit
    printf "Waiting QEMU processes to terminate...\n"
    wait_pid $QEMU_PID0 $QEMU_PID1

    # Kill qemu and snabbswitch instances and clean left over socket files
    kill_pid $QEMU_PID0 $QEMU_PID1 $SNABB_PID0 $SNABB_PID1
    rm_file $NFV_SOCKET0 $NFV_SOCKET1
    printf "Finished.\n"
}

# Check if the script was executed as root
if [ ! $(id -u) = 0 ]; then
    printf "This script must be run as root.\n"
    exit 1
fi

import_env "/etc" || ( printf "No /etc/bench_conf.sh found\n" && exit 1 )
# overrirde from home folder
import_env "$HOME"

# Check if the guest memory will fit in hugetlbfs
PAGES=`cat /proc/meminfo | grep HugePages_Free | awk  '{ print $2; }'`
PAGES=`expr $PAGES \* 2`

TOTAL_MEM=`expr $GUEST_MEM \* $GUESTS`
if [ "$PAGES" -lt "$TOTAL_MEM" ] ; then
    printf "Exiting: Free HugePages are too low!\n"
    printf "Increase /proc/sys/vm/nr_hugepages\n"
    printf "and/or /proc/sys/vm/nr_hugepages_mempolicy\n"
    printf "Hugepages should be set at: (guests memory / 2) + QEMU bookkeeping.\n"
    exit 1
fi

# setup a trap hook
trap on_exit EXIT HUP INT QUIT TERM
