# Lua 5.2.2 Test Suite

This directory contains a modified version of the [Lua 5.2.2 test suite](http://www.lua.org/tests/). The modifications are primarily to disable or amend some tests so that the test suite can be run. 

## LuaJIT build options

LUA 5.2 compatibility must be turned on.

## Running the test suite

You need to have `luajit` on your path.

On UNIX systems just execute:
```
sh run.sh
```
## Platform Status

The modified test suite passes on OSX El Capitan and Ubuntu 14.04. 

## Tests disabled or ignored
Wherever tests have been switched off or ignored a comment has been added and the code has been made conditional. These failures will
be investigated and either the tests will be modified so that they work for LuaJIT or optionally enabled depending upon whether the issue is one of compatibility or a defect in LuaJIT. 

Example of excluded test:
```
-- FIXME tests fail in LuaJIT
-- dofile('main.lua')
```
