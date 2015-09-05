#!/usr/bin/env luajit
-- -*- lua -*-
module(..., package.seeall)

local function Number() return math.random(0, 2^32-1) end

-- A number is always the same as itself plus 0
function property()
   local n = Number()
   return n, n + 0
end
