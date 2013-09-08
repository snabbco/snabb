#!/bin/sh

mkdir -p obj

cd include/luajit-2.0 && make && cd ../..

LIBDIR=include/luajit-2.0/src
INCDIR=include/luajit-2.0/src

# example of how to build a C executable

[ ! -f syscall.lua ] && echo "This script is designed to be run from top level directory" && exit

rm -f ./obj/cbuild
rm -f ./obj/*.{o,a}

# bc.lua  bcsave.lua  dis_arm.lua  dis_mipsel.lua  dis_mips.lua  dis_ppc.lua  dis_x64.lua  dis_x86.lua  dump.lua  v.lua  vmdef.lua

FILES=`find syscall.lua syscall -name '*.lua'`

for f in $FILES
do
  NAME=`echo ${f} | sed 's/\.lua//'`
  MODNAME=`echo ${NAME} | sed 's@/@.@g'`
  luajit -b -t o -n ${MODNAME} ${f} obj/${MODNAME}.o
done

# we will link in hello world
luajit -b -t o -n hello examples/hello.lua obj/hello.o

cc -Wl,-E -o obj/cbuild -I ${INCDIR} examples/cstub.c obj/hello.o ${LIBDIR}/libluajit.a obj/syscall*.o -ldl -lm

./obj/cbuild

