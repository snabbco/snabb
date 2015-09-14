#!/usr/bin/env luajit
-- -*- lua -*-
module(..., package.seeall)

local function Number() return math.random(0, 2^32-1) end

-- This is a trivial property file with a failing property, which is mainly
-- useful for testing pflua-quickcheck for obvious regressions
function property()
   local n = Number()
   return n, n + 1
end
