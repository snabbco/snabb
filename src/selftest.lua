module(...,package.seeall)

local intel = require "intel"
local ffi = require "ffi"
local C = ffi.C
local test = require("test")
local memory = require("memory")

memory.selftest({verbose = true})

print "selftest"
assert(C.lock_memory() == 0)

local nic = intel.new("0000:00:04.0")

print("Initializing controller..")
nic.init()
nic.enable_mac_loopback()
test.waitfor("linkup", nic.linkup, 20, 250000)
nic.selftest({packets=100000})

