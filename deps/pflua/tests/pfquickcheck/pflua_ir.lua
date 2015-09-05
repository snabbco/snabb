#!/usr/bin/env luajit
-- -*- lua -*-
-- This module generates (a subset of) pflua's IR,
-- for property-based tests of pflua internals.

module(..., package.seeall)
local choose = require("pf.utils").choose

local True, False, Fail, ComparisonOp, BinaryOp, Number, Len
local Binary, Arithmetic, Comparison, Conditional
-- Logical intentionally is not local; it is used elsewhere

function True() return { 'true' } end
function False() return { 'false' } end
function Fail() return { 'fail' } end
function ComparisonOp() return choose({ '<', '>' }) end
function BinaryOp() return choose({ '+', '-', '/' }) end
-- Boundary numbers are often particularly interesting; test them often
function Number()
   if math.random() < 0.2
      then return math.random(0, 2^32 - 1)
   else
      return choose({ 0, 1, 2^31-1, 2^31, 2^32-1 })
   end
end
function Len() return 'len' end
function Binary(db)
   local op, lhs, rhs = BinaryOp(), Arithmetic(db), Arithmetic(db)
   if op == '/' then table.insert(db, { '!=', rhs, 0 }) end
   return { 'uint32', { op, lhs, rhs } }
end
function PacketAccess(db)
   local pkt_access_size = choose({1, 2, 4})
   local position = Arithmetic(db)
   table.insert(db, {'>=', 'len', {'+', position, pkt_access_size}})
   local access = { '[]', position, pkt_access_size }
   if pkt_access_size == 1 then return access end
   if pkt_access_size == 2 then return { 'ntohs', access } end
   if pkt_access_size == 4 then return { 'uint32', { 'ntohs', access } } end
   error('unreachable')
end
function Arithmetic(db)
   return choose({ Binary, Number, Len, PacketAccess })(db)
end
function Comparison()
   local asserts = {}
   local expr = { ComparisonOp(), Arithmetic(asserts), Arithmetic(asserts) }
   for i=#asserts,1,-1 do
      expr = { 'if', asserts[i], expr, { 'fail' } }
   end
   return expr
end
function Conditional() return { 'if', Logical(), Logical(), Logical() } end
function Logical()
   return choose({ Conditional, Comparison, True, False, Fail })()
end
