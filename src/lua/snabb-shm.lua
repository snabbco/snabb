#!/usr/bin/env luajit
-- Copyright 2012 Snabb Gmbh.

local ffi = require("ffi")

ffi.cdef(io.open("/home/luke/hacking/QEMU/net/snabb-shm-dev.h"):read("*a"))

print("loaded ffi'ery")
print(ffi.sizeof("struct snabb_shm_dev"))

local shm = ffi.new("struct snabb_shm_dev")
shm.magic = 0x57ABB000
shm.version = 1

print(shm.magic)

print("writing file..")

io.output("/tmp/shm", "w")
io.write(ffi.string(shm, ffi.sizeof(shm)))
io.close()

