#!/bin/bash

. defs.sh

OPTS="-p"
SEND_WASTE=0

sudo taskset 010 env LD_LIBRARY_PATH=$LIBPATH ./recv $OPTS $RECV_DEV &
sleep 1
sudo taskset 020 env LD_LIBRARY_PATH=$LIBPATH ./send -w $SEND_WASTE $OPTS $SEND_DEV $(ifconfig $RECV_DEV | perl -ne 'print $1 if (/HWaddr (\S*)/)')
