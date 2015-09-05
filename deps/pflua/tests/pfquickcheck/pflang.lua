#!/usr/bin/env luajit
-- -*- lua -*-
-- This module generates (a subset of) pflang, libpcap's filter language

-- Convention: initial uppercase letter => generates pflang expression
-- initial lowercase letter => aux helper

-- Mutability discipline:
-- Any function may mutate results it calls into being.
-- No function may mutate its arguments; it must copy,
-- mutate the copy, and return instead.

module(..., package.seeall)
local choose = require("pf.utils").choose
local utils = require("pf.utils")

local verbose = os.getenv("PF_VERBOSE_PFLANG")

local function Empty() return { "" } end

local function uint8() return math.random(0, 2^8-1) end

local function uint16() return math.random(0, 2^16-1) end

-- Boundary numbers are often particularly interesting; test them often
local function uint32()
   if math.random() < 0.2
      then return math.random(0, 2^32 - 1)
   else
      return choose({ 0, 1, 2^31-1, 2^31, 2^32-1 })
   end
end

-- Given something like { 'host', '127.0.0.1' }, make it sometimes
-- start with src or dst. This should only be called on expressions
-- which can start with src or dst!
local function optionally_add_src_or_dst(expr)
   local r = math.random()
   local e = utils.dup(expr)
   if r < 1/3 then table.insert(e, 1, "src")
   elseif r < 2/3 then table.insert(e, 1, "dst")
   end -- else: leave it unchanged
   return e
end

local function andSymbol()
   local r = math.random()
   if r < 1/2 then return "&&" else return "and" end
end

local function orSymbol()
   local r = math.random()
   if r < 1/2 then return "||" else return "or" end
end

local function notSymbol()
   local r = math.random()
   if r < 1/2 then return "!" else return "not" end
end

local function optionally_not(expr)
   local r = math.random()
   local e = utils.dup(expr)
   if r < 1/2 then
      table.insert(e, 1, notSymbol()) end
   return e
end

local function IPProtocol()
   return choose({"icmp", "igmp", "igrp", "pim", "ah", "esp", "vrrp",
                   "udp", "tcp", "sctp", "icmp6", "ip", "arp", "rarp", "ip6"})
end

local function ProtocolName()
   return { IPProtocol() }
end

-- TODO: add names?
local function portNumber()
   return math.random(1, 2^16 - 1)
end

local function Port()
   return { "port", portNumber() }
end

local function PortRange()
   local port1, port2 = portNumber(), portNumber()
   return { "portrange", port1 .. '-' .. port2 }
end

local function ProtocolWithPort()
   protocol = choose({ "tcp", "udp" })
   return { protocol, "port", portNumber() }
end

-- TODO: generate other styles of ipv4 address
local function ipv4Addr()
   return table.concat({ uint8(), uint8(), uint8(), uint8() }, '.')
end

-- TODO: generate ipv6 addresses
local function Host()
   return optionally_add_src_or_dst({ 'host', ipv4Addr() })
end

local function netmask() return math.random(0, 32) end

-- This function is overly conservative with zeroing octets.
-- TODO: zero more precisely?
function netspec()
   local mask = netmask()
   local o1, o2, o3, o4 = uint8(), uint8(), uint8(), uint8()
   if mask < 32 then o4 = 0 end
   if mask < 24 then o3 = 0 end
   if mask < 16 then o2 = 0 end
   if mask < 8 then o1 = 0 end
   local addr = table.concat({ o1, o2, o3, o4 }, '.')
   return addr .. '/' .. mask
end

function Net()
   return optionally_add_src_or_dst({ 'net', netspec() })
end

-- ^ intentionally omitted; 'len < 1 ^ 1' is not valid pflang
-- in older versions of libpcap
local function binaryMathOp()
   return choose({ '+', '-', '/', '*', '|', '&' })
end

local function shiftOp() return choose({ '<<', '>>' }) end

local function comparisonOp()
   return choose({ '<', '>', '<=', ">=", '=', '!=', '==' })
end

-- Generate simple math expressions.
-- Don't recurse, to limit complexity; more complex math tests are elsewhere.
local function binMath(numberGen)
   -- create numbers with the given function, or uint32 by default
   if not numberGen then numberGen = uint32 end
   local r, n1, n2, b = math.random()
   if r < 0.2 then
      n1, n2, b = numberGen(), math.random(0, 31), shiftOp()
   else
      n1, n2, b = numberGen(), numberGen(), binaryMathOp()
      -- Don't divide by 0; that's tested elsewhere
      if b == '/' then while n2 == 0 do n2 = numberGen() end end
   end
   return n1, n2, b
end

-- Filters like 1+1=2 are legitimate pflang, as long as the result is right
local function Math()
   local n1, n2, b = binMath()
   local result
   if b == '*' then
      result = n1 * 1LL * n2 -- force non-floating point
      result = tonumber(result % 2^32) -- Yes, this is necessary
   elseif b == '/' then result = math.floor(n1 / n2)
   elseif b == '-' then result = n1 - n2
   elseif b == '+' then result = n1 + n2
   elseif b == '|' then result = bit.bor(n1, n2)
   elseif b == '&' then result = bit.band(n1, n2)
   elseif b == '>>' then result = bit.rshift(n1, n2)
   elseif b == '<<' then result = bit.lshift(n1, n2)
   else error("Unhandled math operator " .. b) end
   result = result % 2^32 -- doing this twice for * is fine
   return { n1, b, n2, '=', result }
end

-- Generate uint16s instead of uint32s to avoid triggering
-- libpcap bug 434.
local function LenWithMath()
   local r = math.random()
   local comparison = comparisonOp()
   if r < 0.1 then
      return { 'len', comparison, uint16() }
   else
      local n1, n2, b = binMath(uint16)
      return { 'len', comparison, n1, b, n2 }
   end
end

-- TODO: use uint32 and ipv6 jumbo packets at some point?
local function packetAccessLocation()
   local r1, r2 = math.random(), math.random()
   local base
   -- Usually generate small accesses - more likely to be in range
   if r1 < 0.9 then
      base = uint8()
   else
      base = uint16()
   end
   if r2 < 0.5 then
      return tostring(base)
   else
      -- tcpdump only allows the following 3 numbers of bytes
      local bytes = choose({1,2,4})
      return base .. ':' .. bytes
   end
end

local function PacketAccess()
   local proto = ProtocolName()[1]
   -- Avoid packet access on protocols where libpcap doesn't allow it
   -- libpcap does not allow 'ah' and 'esp' packet access; not a pflua bug.
   -- libpcap does not allow icmp6[x]:
   -- "IPv6 upper-layer protocol is not supported by proto[x]"
   local skip_protos = utils.set('ah', 'esp', 'icmp6')
   while skip_protos[proto] do
      proto = ProtocolName()[1]
   end
   local access = packetAccessLocation()
   -- Hack around libpcap bug 430
   -- libpcap's match status depends on optimization levels if the access
   -- is out of bounds.
   -- Use len + 54 as a conservative bounds check; it gives room for
   -- an ethernet header and an ipv6 fixed-length header. It's not ideal.
   local header_guard = 54 -- ethernet + ipv6; most others are smaller
   local access_loc = access:match("^%d+")
   local guard = table.concat({'len >= ', access_loc, '+', header_guard}, ' ')
   local comparison = table.concat({comparisonOp(), uint8()}, ' ')
   local pkt_access = table.concat({proto, '[', access, '] '})
   return {'(', guard, 'and', pkt_access, comparisonOp(), uint8(), ')'}
end

local function PflangClause()
   return choose({ProtocolName, Port, PortRange, ProtocolWithPort,
                  Host, Net, Math, LenWithMath, PacketAccess})()
end

-- Add logical operators (or/not)
function PflangLogical()
   local function PflangLogicalRec(depth, expr)
      local r = math.random()
      if depth <= 0 then return expr end

      if r < 0.9 then
         local pclause2 = PflangClause()
         local logicOp = orSymbol()
         if r < 0.45 then logicOp = andSymbol() end

         table.insert(expr, logicOp)
         for _,v in ipairs(pclause2) do table.insert(expr, v) end
         return PflangLogicalRec(depth - 1, optionally_not(expr))
      else
         return PflangLogicalRec(depth - 1, optionally_not(expr))
      end
   end

   return PflangLogicalRec(math.random(1, 5), PflangClause())
end

function Pflang()
   local r = math.random()
   if r < 0.001 then return Empty() end
   local expr = choose({ PflangClause, PflangLogical })()
   if verbose then print(table.concat(expr, ' ')) end
   return expr
end
