#!/bin/sh

OPTS="-p"
LIBPATH=$HOME/openonload-201310-u3/build/gnu_x86_64/lib/ciul

sudo taskset 010 env LD_LIBRARY_PATH=$LIBPATH ./efsendrecv $OPTS recv p10p1 192.168.99.1 1201 00:0f:53:0c:d5:3d 192.168.99.2 1202 < /dev/null &
sleep 1
sudo taskset 020 env LD_LIBRARY_PATH=$LIBPATH  ./efsendrecv $OPTS send p10p2 192.168.99.2 1202 00:0f:53:0c:d5:3c 192.168.99.1 1201
