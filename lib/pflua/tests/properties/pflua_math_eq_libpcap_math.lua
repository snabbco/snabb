#!/usr/bin/env luajit
-- -*- lua -*-
module(..., package.seeall)
package.path = package.path .. ";../?.lua;../../src/?.lua"
local pflang_math = require("pfquickcheck.pflang_math")

function property()
   arithmetic_expr = table.concat(pflang_math.PflangArithmetic(), ' ')
   local libpcap_result = pflang_math.libpcap_eval(arithmetic_expr)
   local pflua_result = pflang_math.pflua_eval(arithmetic_expr)
   return libpcap_result, pflua_result
end

function print_extra_information()
   print(("The arithmetic expression was %s"):format(arithmetic_expr))
end
