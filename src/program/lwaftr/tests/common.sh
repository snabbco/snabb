#!/usr/bin/env bash

SKIPPED_CODE=43

# Show $1 as error message and exit with code $2, or 1 if not passed.
function exit_on_error {
    (>&2 echo $1)
    if [[ -n "$2" ]]; then
        exit $2
    else
        exit 1
    fi
}

# Check that the script is run as root, otherwise exit.
function check_for_root {
    if [[ $EUID != 0 ]]; then
        exit_on_error "This script must be run as root"
    fi
}

# Check that a command is available, otherwise exit with code $SKIPPED_CODE.
function check_command_available {
    which "$1" &> /dev/null
    if [[ $? -ne 0 ]]; then
       exit_on_error "No $1 tool present, unable to run test." $SKIPPED_CODE
    fi
}

# Check that NIC interfaces are available, otherwise exit with code $SKIPPED_CODE.
function check_nics_available {
    if [[ -z "$SNABB_PCI0" ]]; then
        exit_on_error "SNABB_PCI0 not set, skipping $1" $SKIPPED_CODE
    fi
    if [[ -z "$SNABB_PCI1" ]]; then
        exit_on_error "SNABB_PCI1 not set, skipping $1" $SKIPPED_CODE
    fi
}

# Check that a file exists, otherwise exit.
# If the second argument is "--remove", remove the file.
function assert_file_exists {
    if [[ ! -f "$1" ]]; then
        exit_on_error "File $1 does not exists."
    fi
    if [[ "$2" == "--remove" ]]; then
        rm -f "$1"
    fi
}

# Check equality of the first two arguments.
# The third argument will be displayed if the check fails.
# e.g.
#  $ assert_equal "yellow "cat"                   -> error
#  $ assert_equal "yellow "cat" "Cat not yellow"  -> error with message
#  $ assert_equal "banana" "banana"               -> nothing (valid)
function assert_equal {
    if [[ -z "$2" ]]; then
        exit_on_error "assert_equal: not enough arguments."
        exit 1
    fi
    if [[ "$1" == "$2" ]]; then
        return
    else
        if [[ -z "$3" ]]; then
            exit_on_error "Error: $1 != $2"
        else
            exit_on_error "Error: $3"
        fi
    fi
}
