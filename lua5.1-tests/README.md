# Lua 5.1 Test Suite

This directory contains a modified version of the Lua 5.1 test suite. The modifications are primarily to disable or amend some tests 
so that the test suite can be run. 

## LuaJIT build options

Some tests will fail if LUA 5.2 compatibility is turned on.

## Running the test suite

You need to have `luajit` on your path.

On UNIX systems just execute:
```
sh run.sh
```

## Tests disabled or ignored
Wherever tests have been switched off or ignored a comment has been added and the code has been made conditional. These failures will
be investigated and either the tests will be modified or permanently disabled depending upon whether the issue is one of compatibility 
or a defect in LuaJIT. 

Example of excluded test:
```
-- FIXME tests fail in LuaJIT
-- dofile('main.lua')
```
