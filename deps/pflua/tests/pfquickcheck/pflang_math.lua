#!/usr/bin/env luajit
module(..., package.seeall)

local io = require("io")
local codegen = require("pf.backend")
local expand = require("pf.expand")
local parse = require("pf.parse")
local pfcompile = require("pfquickcheck.pfcompile")
local libpcap = require("pf.libpcap")
local bpf = require("pf.bpf")
local utils = require("pf.utils")

-- Generate pflang arithmetic
local PflangNumber, PflangSmallNumber, PflangOp
function PflangNumber() return math.random(0, 2^32-1) end
function PflangOp() return utils.choose({ '+', '-', '*', '/' }) end
function PflangArithmetic()
   return { PflangNumber(), PflangOp(), PflangNumber() }
end

-- Evaluate math expressions with libpcap and pflang's IR

-- Pflang allows arithmetic as part of larger expressions.
-- This tool uses len < arbitrary_arithmetic_here as a scaffold
function libpcap_eval(str_expr)
   local expr = "len < " .. str_expr
   local asm = libpcap.compile(expr, 'RAW')
   local asm_str = bpf.disassemble(asm)
   local template = "^000: A = length\
001: if %(A >= (%d+)%) goto 2 else goto 3\
002: return 0\
003: return 65535\
$"
   local constant_str = asm_str:match(template)
   if not constant_str then error ("unexpected bpf: "..asm_str) end
   local constant = assert(tonumber(constant_str), constant_str)
   assert(0 <= constant and constant < 2^32, constant)
   return constant
end

-- Here is an example of the pflua output that is parsed
--return function(P,length)
--   return length < ((519317859 + 63231) % 4294967296)
--end

-- Old style:
-- return function(P,length)
--    local v1 = 3204555350 * 122882
--    local v2 = v1 % 4294967296
--    do return length < v2 end
-- end

function pflua_eval(str_expr)
   local expr = "len < " .. str_expr
   local ir = expand.expand(parse.parse(expr))
   local filter = pfcompile.compile_lua_ast(ir, "Arithmetic check")
   -- Old style:
   --  local math_string = string.match(filter, "v1 = [%d-+/*()%a. ]*")
   local math_str = string.match(filter, "return length < ([%d%a %%-+/*()]*)")
   math_str = "v1 = " .. math_str
   -- Loadstring has a different env, so floor doesn't resolve; use math.floor
   math_str = math_str:gsub('floor', 'math.floor')
   v1 = nil
   loadstring(math_str)() -- v1 must not be local, or this approach will fail
   -- v1 should always be within [0..2^32-1]
   assert(v1 >= 0)
   assert (v1 < 2^32)
   assert(v1 == math.floor(v1))
   return v1
end
