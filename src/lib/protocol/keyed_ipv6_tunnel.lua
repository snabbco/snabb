-- This is an implementation of the "Keyed IPv6 Tunnel" specification
-- conforming to
-- http://tools.ietf.org/html/draft-mkonstan-keyed-ipv6-tunnel-01.  It
-- uses a particular variant of the L2TPv3 encapsulation that uses no
-- L2 sublayer header and a fixed cookie of 64 bits.  It is only
-- specified for IPv6 as transport protocol.
--
-- It makes use of the same IP protocol number 115 as L2TPv3, which
-- makes it hard to demultiplex, because the L2TPv3 header itself does
-- not contain sufficient information.  There are currently no
-- implementations of other modes of L2TPv3 in Snabbswitch and protocol
-- number 115 is simply mapped to this module from the IPv6 header
-- class.

module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local header = require("lib.protocol.header")
local lib = require("core.lib")
local htonl, ntohl = lib.htonl, lib.ntohl

ffi.cdef[[
      typedef union {
         uint8_t  cookie[8];
         uint64_t cookie_64bit;
      } cookie_t;
]]

local tunnel_header_t = ffi.typeof[[
      struct {
         uint32_t session_id;
         cookie_t cookie;
      } __attribute__((packed))
]]

local tunnel = subClass(header)
local cookie_t =
   ffi.metatype(ffi.typeof("cookie_t"),
                {
                   __tostring =
                      function (c)
                         local s = { "0x" }
                         for i = 0, 7 do
                            table.insert(s, string.format("%02x", c.cookie[i]))
                         end
                         return table.concat(s)
                      end,
                   __eq =
                      function(lhs, rhs)
                         return rhs and lhs.cookie_64bit == rhs.cookie_64bit
                      end
                })

-- Class variables
tunnel._name = "keyed ipv6 tunnel"
tunnel._header_type = tunnel_header_t
tunnel._header_ptr_type = ffi.typeof("$*", tunnel_header_t)
tunnel._ulp = {}

-- Class methods

function tunnel:new (config)
   local o = tunnel:superClass().new(self)
   -- The spec for L2TPv3 over IPv6 recommends to set the session ID
   -- to 0xffffffff for the "static 1:1 mapping" scenario.
   o:session_id(config.session_id or 0xffffffff)
   o:cookie(config.cookie or '\x00\x00\x00\x00\x00\x00\x00\x00')
   return o
end

function tunnel:new_from_mem (mem, size)
   local o = tunnel:superClass().new_from_mem(self, mem, size)
   if o:session_id() == 0 then
      -- Session ID 0 is reserved for L2TPv3 control messages
      o:free()
      return nil
   end
   return o
end

function tunnel:new_cookie (s)
   assert(type(s) == 'string' and string.len(s) == 8,
          'invalid cookie')
   local c = cookie_t()
   ffi.copy(c.cookie, s, 8)
   return c
end

-- Instance methods

function tunnel:session_id (id)
   local h = self:header()
   if id ~= nil then
      assert(id ~= 0, "invalid session id 0")
      h.session_id = htonl(id)
   else
      return ntohl(h.session_id)
   end
end

function tunnel:cookie (c)
   local h = self:header()
   if c ~= nil then
      h.cookie.cookie_64bit = c.cookie_64bit
   else
      return h.cookie
   end
end

return tunnel
