
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
