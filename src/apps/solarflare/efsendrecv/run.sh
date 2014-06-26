#!/bin/sh

OPTS="-p"
LIBPATH=$HOME/openonload-201310-u3/build/gnu_x86_64/lib/ciul

sudo taskset 010 env LD_LIBRARY_PATH=$LIBPATH ./recv $OPTS p10p1 &
sleep 1
sudo taskset 020 env LD_LIBRARY_PATH=$LIBPATH ./send -w 120 $OPTS p10p2 00:0f:53:0c:d5:3c
