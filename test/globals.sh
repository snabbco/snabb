#!/bin/sh

EXIT=0

# test for use of globals variables in ways that are not allowed

# test for set globals, never allowed

GSET=`find syscall syscall.lua -name '*.lua' | xargs -n1 luajit -bl | grep GSET`

if [ ! -z "$GSET" ]
then
  echo "Error: global variable set"
  find syscall syscall.lua -name '*.lua' | xargs -n1 luajit -bl | egrep "BYTECODE|GSET"
  EXIT=1
fi

# test for get globals, only allowed at top of file for specific cases
# this is not a complete test the local assignment could be missing
# these are the ones we use at present

OK="require|print|error|assert|tonumber|tostring|setmetatable|pairs|ipairs|unpack|rawget|rawset|pcall|type|table|string|math|select"

GGET=`find syscall syscall.lua -name '*.lua' | xargs -n1 luajit -bl | grep GGET | egrep -v "$OK"`

if [ ! -z "$GGET" ]
then
  echo "Error: global variable get"
  find syscall syscall.lua -name '*.lua' | xargs -n1 luajit -bl | egrep -v "$OK" | egrep "BYTECODE|GGET"
  EXIT=1
fi

exit $EXIT

