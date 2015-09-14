#!/usr/bin/env luajit
-- -*- lua -*-
module(..., package.seeall)
package.path = package.path .. ";../?.lua;../../src/?.lua"

local pflua_ir = require('pfquickcheck.pflua_ir')

local function generate(seed)
   math.randomseed(seed)
   local res
   -- Loop a few times so that we stress JIT compilation; see
   -- https://github.com/Igalia/pflua/issues/77.
   for i=1,100 do res = pflua_ir.Logical() end
   return res
end

function property(packets, filter_list)
   local seed = math.random()
   return generate(seed), generate(seed)
end
