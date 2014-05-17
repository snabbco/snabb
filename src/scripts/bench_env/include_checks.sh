# Check if the script was executed as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

# Check if configuration file is present on home directory
ENV_FILE="${HOME}/bench_conf.sh"

source $ENV_FILE || \
{
        echo "Configuration file missing!" && \
        echo "Copy $ENV_FILE to your home directory and modify accordingly." && \
        exit 1
}

echo "Sourced $ENV_FILE"
echo -e "\n------"
cat $ENV_FILE
echo -e "------\n"

# Check if the guest memory will fit in hugetlbfs
PAGES=`cat /proc/meminfo | grep HugePages_Free`
PAGES=${PAGES:16}
PAGES=`expr $PAGES \* 2`

TOTAL_MEM=`expr $GUEST_MEM \* $GUESTS`
if [ "$PAGES" -lt "$TOTAL_MEM" ] ; then
        echo "Exiting: Free HugePages are too low!"
        echo "Increase /proc/sys/vm/nr_hugepages"
        echo "and/or /proc/sys/vm/nr_hugepages_mempolicy"
        echo "Hugepages should be set at: (guests memory / 2) + QEMU bookkeeping."
        exit 1
fi

