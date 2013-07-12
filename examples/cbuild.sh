#!/bin/sh

# fix as appropriate for your setup
LIBDIR=/usr/local/lib
INCDIR=/usr/local/include/luajit-2.0

# example of how to build a C executable

[ ! -f syscall.lua ] && echo "This script is designed to be run from top level directory" && exit

./examples/bytecode.sh || ("Bytecode build failed" && exit)

# we will link in hello world
luajit -b -t o -n hello examples/hello.lua obj/hello.o

cc -Wl,-E -o obj/cbuild -I ${INCDIR} examples/cstub.c obj/hello.o ${LIBDIR}/libluajit-5.1.a obj/ljsyscall.a -ldl -lm

./obj/cbuild

