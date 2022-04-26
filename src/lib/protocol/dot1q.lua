-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)
local ffi = require("ffi")
local lib = require("core.lib")
local header = require("lib.protocol.header")
local ntohs, htons = lib.ntohs, lib.htons

local dot1q = subClass(header)

-- Class variables
dot1q._name = "dot1q"
dot1q._ulp = {
   class_map = {
                  [0x0800] = "lib.protocol.ipv4",
                  [0x86dd] = "lib.protocol.ipv6",
                },
   method    = 'type' }
dot1q:init(
   {
      [1] = ffi.typeof[[
            struct {
               uint16_t pcp_dei_vid;
               uint16_t ether_type;
            } __attribute__((packed))
      ]]
   })

dot1q.TPID = 0x8100

-- Class methods

function dot1q:new (config)
   local o = dot1q:superClass().new(self)
   o:id(config.id)
   o:type(config.type)
   return o
end

-- Instance methods

function dot1q:id (id)
   local h = self:header()
   if id ~= nil then
      h.pcp_dei_vid = htons(id)
   else
      return(ntohs(h.pcp_dei_vid))
   end
end

function dot1q:type (t)
   local h = self:header()
   if t ~= nil then
      h.ether_type = htons(t)
   else
      return(ntohs(h.ether_type))
   end
end

return dot1q
