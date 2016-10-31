-- Use of this source code is governed by the Apache 2.0 license; see
-- COPYING.
module(..., package.seeall)

local util = require("lib.yang.util")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local ethernet = require("lib.protocol.ethernet")

-- FIXME:
-- Parse inet:mac-address using ethernet:pton
-- Parse inet:ipv4-address using ipv4:pton
-- Parse inet:ipv6-address using ipv6:pton
-- Parse inet:ipv4-prefix?
-- Parse inet:ipv6-prefix?

types = {}

local function integer_type(min, max)
   local ret = {}
   function ret.parse(str, what)
      return util.tointeger(str, what, min, max)
   end
   function ret.tostring(val)
      local str = tostring(val)
      if str:match("ULL") then return str:sub(1, -4)
      elseif str:match("LL") then return str:sub(1, -3)
      else return str end
   end
   return ret
end

types.int8 = integer_type(-0xf0, 0x7f)
types.int16 = integer_type(-0xf000, 0x7fff)
types.int32 = integer_type(-0xf000000, 0x7fffffff)
types.int64 = integer_type(-0xf00000000000000LL, 0x7fffffffffffffffLL)
types.uint8 = integer_type(0, 0xff)
types.uint16 = integer_type(0, 0xffff)
types.uint32 = integer_type(0, 0xffffffff)
types.uint64 = integer_type(0, 0xffffffffffffffffULL)

local function unimplemented(type_name)
   local ret = {}
   function ret.parse(str, what)
      error('unimplemented '..type_name..' when parsing '..what)
   end
   function ret.tostring(val)
      return tostring(val)
   end
   return ret
end

types.binary = unimplemented('binary')
types.bits = unimplemented('bits')

types.boolean = {}
function types.boolean.parse(str, what)
   local str = assert(str, 'missing value for '..what)
   if str == 'true' then return true end
   if str == 'false' then return false end
   error('bad boolean value: '..str)
end
function types.boolean.tostring(val)
   return tostring(val)
end

types.decimal64 = unimplemented('decimal64')
types.empty = unimplemented('empty')
types.identityref = unimplemented('identityref')
types['instance-identifier'] = unimplemented('instance-identifier')
leafref = unimplemented('leafref')

types.string = {}
function types.string.parse(str, what)
   return assert(str, 'missing value for '..what)
end
function types.string.tostring(val)
   return val
end

types.union = unimplemented('union')

types['ipv4-address'] = {
   parse = function(str, what) return assert(ipv4:pton(str)) end,
   tostring = function(val) return ipv4:ntop(val) end
}

types['ipv6-address'] = {
   parse = function(str, what) return assert(ipv6:pton(str)) end,
   tostring = function(val) return ipv6:ntop(val) end
}

types['mac-address'] = {
   parse = function(str, what) return assert(ethernet:pton(str)) end,
   tostring = function(val) return ethernet:ntop(val) end
}

types['ipv4-prefix'] = {
   parse = function(str, what)
      local prefix, len = str:match('^([^/]+)/(.*)$')
      return { assert(ipv4:pton(prefix)), util.tointeger(len, 1, 32) }
   end,
   tostring = function(val) return ipv4:ntop(val[1])..'/'..tostring(val[2]) end
}

types['ipv6-prefix'] = {
   parse = function(str, what)
      local prefix, len = str:match('^([^/]+)/(.*)$')
      return { assert(ipv6:pton(prefix)), util.tointeger(len, 1, 128) }
   end,
   tostring = function(val) return ipv6:ntop(val[1])..'/'..tostring(val[2]) end
}

function selftest()
   assert(types['uint8'].parse('100') == 100)
end
