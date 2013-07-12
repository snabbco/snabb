#!/bin/sh

# script to make archive that can be linked into a binary

# TODO rewrite in Lua, we should dogfood...

[ ! -f syscall.lua ] && echo "This script is designed to be run from top level directory" && exit

mkdir -p obj

rm -f ./obj/*.{o,a}

ARCH=`luajit -e "S=require'syscall';print(S.abi.arch)"`
OS=`luajit -e "S=require'syscall';print(S.abi.os)"`

FILES=`find syscall.lua syscall -name '*.lua'`

for f in $FILES
do
  NAME=`echo ${f} | sed 's/\.lua//'`
  MODNAME=`echo ${NAME} | sed 's@/@.@g'`
  luajit -b -t o -n ${MODNAME} ${f} obj/${MODNAME}.o
done

ar cr obj/ljsyscall.a obj/*.o # all files

