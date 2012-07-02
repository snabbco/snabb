#!/usr/bin/env luajit
-- Copyright 2012 Snabb Gmbh.

print("Snabb: Quick solutions for big networks.")

local ffi = require("ffi")
local fabric = ffi.load("fabric")

ffi.cdef[[
      void test();
]]

fabric.test()


