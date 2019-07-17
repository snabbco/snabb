-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local header = require("lib.protocol.header")
local lib = require("core.lib")
local ipsum = require("lib.checksum").ipsum

-- XXX IPv4 and IPv6 use the same ICMP header format but distinct
-- number spaces for type and code.  This class needs to be subclassed
-- accordingly.

local icmp = subClass(header)

-- Class variables
icmp._name = "icmp"
icmp._ulp = {
   class_map = { [2]   = "lib.protocol.icmp.ptb",
                 [135] = "lib.protocol.icmp.nd.ns",
                 [136] = "lib.protocol.icmp.nd.na" },
   method    = "type" }
icmp:init(
   {
      [1] = ffi.typeof[[
            struct {
               uint8_t type;
               uint8_t code;
               int16_t checksum;
            } __attribute__((packed))
      ]]
   })

-- Class methods

function icmp:new (type, code)
   local o = icmp:superClass().new(self)
   o:type(type)
   o:code(code)
   return o
end

-- Instance methods

function icmp:type (type)
   if type ~= nil then
      self:header().type = type
   else
      return self:header().type
   end
end

function icmp:code (code)
   if code ~= nil then
      self:header().code = code
   else
      return self:header().code
   end
end

local function checksum(header, payload, length, ipv6)
   local csum = 0
   if ipv6 then
      -- Checksum IPv6 pseudo-header
      local ph = ipv6:pseudo_header(length + ffi.sizeof(header), 58)
      csum = ipsum(ffi.cast("uint8_t *", ph), ffi.sizeof(ph), 0)
   end
   -- Add ICMP header
   local csum_rcv = header.checksum
   header.checksum = 0
   csum = ipsum(ffi.cast("uint8_t *", header),
                ffi.sizeof(header), bit.bnot(csum))
   header.checksum = csum_rcv
   -- Add ICMP payload
   return ipsum(payload, length, bit.bnot(csum))
end

function icmp:checksum (payload, length, ipv6)
   local header = self:header()
   header.checksum = lib.htons(checksum(header, payload, length, ipv6))
end

function icmp:checksum_check (payload, length, ipv6)
   return checksum(self:header(), payload, length, ipv6) == lib.ntohs(self:header().checksum)
end

return icmp
