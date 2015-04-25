-- conntrack.lua -- Connection tracking for IPv4/IPv6 TCP/UDP sessions
--
-- This module exposes the following API:
--
--  define(tablename, agestep)
--    define a named connection tracking table.
--    agestep is the duration in seconds before a connection ages from
--    states new to old, old to deleted. The default is 7200 (2 hours).
--
--  track(tablename, buffer)
--    Insert an entry into a connection table based on the packet
--    headers in the buffer.
--
--  check(tablename, buffer) => flag
--    Return true if the buffer contains a packet for a connection
--    that is already tracked in the table.
--
--  ageall()
--    Age all connection tables (based on wall-clock time) to remove
--    timed-out connections.
--
--  clear()
--    Remove all connection entries.

local ffi = require 'ffi'
local lib = require 'core.lib'

local ETHERTYPE_IPV6 = 0xDD86
local ETHERTYPE_IPV4 = 0x0008

local IP_UDP = 0x11
local IP_TCP = 6
local IP_ICMP = 1
local IPV6_ICMP = 0x3a

local ETHERTYPE_OFFSET = 12

local IPV4_SOURCE_OFFSET = 26
local IPV4_DEST_OFFSET = 30
local IPV4_PROTOCOL_OFFSET = 23
local IPV4_SOURCE_PORT_OFFSET = 34
local IPV4_DEST_PORT_OFFSET = 36
local IPV4_TCP_FLAGS = 47

local IPV6_SOURCE_OFFSET = 22
local IPV6_DEST_OFFSET = 38
local IPV6_NEXT_HEADER_OFFSET = 20 -- protocol
local IPV6_SOURCE_PORT_OFFSET = 54
local IPV6_DEST_PORT_OFFSET = 56
local IPV6_TCP_FLAGS = 67


---
--- connection spec structures
---

ffi.cdef [[
   typedef struct {
      uint32_t src_ip, dst_ip;
      uint16_t src_port, dst_port;
      uint8_t protocol;
   } __attribute__((packed)) conn_spec_ipv4;

   typedef struct {
      uint64_t a, b;
   } __attribute__((packed)) ipv6_addr;

   typedef struct {
      ipv6_addr src_ip, dst_ip;
      uint16_t src_port, dst_port;
      uint8_t protocol;
   } __attribute__((packed)) conn_spec_ipv6;
]]

----

local conntrack
do
   local conntracks = {}
   local counts = {}
   local time = engine.now
   local function new() return {{}, {}, time()} end
   local function put(p, k, v)
      local isnew = p[1][k] == nil
      p[1][k] = v
      return isnew
   end
   local function get(p, k) return p[1][k] or p[2][k] end
   local function age(p, t)
      if time() > p[3]+t then
         p[1], p[2], p[3] = {}, p[1], time()
         return true
      end
   end

   conntrack = {
      define = function (name)
         if not name then return end
         conntracks[name] = conntracks[name] or new()
         counts[name] = counts[name] or 0
      end,

      track = function (name, key, revkey, limit)
         limit = limit or 1000
         local p = conntracks[name]
         if counts[name] > limit then
            if age(p, 0.01) then
               counts[name] = 0
            end
         end
         if put(p, key, true) then
            counts[name] = counts[name] + 1
         end
         put(p, revkey, true)
      end,

      check = function (name, key)
         return key and get(conntracks[name], key)
      end,

      age = function(name, t)
         if name and age(conntracks[name], t or 7200) then
            counts[name] = 0
         end
      end,

      clear = function ()
         for name, p in pairs(conntracks) do
            p[1], p[2], p[3] = {}, {}, time()
         end
         conntracks = {}
      end,
   }
end

-----------------

local genspec = {}

function genspec:reverse(o)
   if o then
      o.protocol = self.protocol
   else
      o = self
   end
   o.src_ip, o.dst_ip = self.dst_ip, self.src_ip
   o.src_port, o.dst_port = self.dst_port, self.src_port
   return o
end


function genspec:__tostring()
   return ffi.string(self, ffi.sizeof(self))
end

function genspec:check(trackname)
   return conntrack.check(trackname, self:__tostring())
end


----


local spec_v4 = ffi.typeof('conn_spec_ipv4')
local ipv4 = {
   __tostring  = genspec.__tostring,
   reverse = genspec.reverse,
   check = genspec.check
}
ipv4.__index = ipv4


function ipv4:fill(b)
   do
      local hdr_ips = ffi.cast('uint32_t*', b+IPV4_SOURCE_OFFSET)
      self.src_ip = hdr_ips[0]
      self.dst_ip = hdr_ips[1]
   end
   self.protocol = b[IPV4_PROTOCOL_OFFSET]
   if self.protocol == IP_TCP or self.protocol == IP_UDP then
      local hdr_ports = ffi.cast('uint16_t*', b+IPV4_SOURCE_PORT_OFFSET)
      self.src_port = hdr_ports[0]
      self.dst_port = hdr_ports[1]
   else
      self.src_port, self.dst_port = 0, 0
   end
   return self
end


do
   local s2 = nil
   function ipv4:track(trackname)
      s2 = s2 or spec_v4()
      return conntrack.track(trackname, self:__tostring(), self:reverse(s2):__tostring())
   end
end


spec_v4 = ffi.metatype(spec_v4, ipv4)

-------


local spec_v6 = ffi.typeof('conn_spec_ipv6')
local ipv6 = {
   __tostring  = genspec.__tostring,
   reverse = genspec.reverse,
   check = genspec.check
}
ipv6.__index = ipv6

function ipv6:fill(b)
   do
      local hdr_ips = ffi.cast('ipv6_addr*', b+IPV6_SOURCE_OFFSET)
      self.src_ip = hdr_ips[0]
      self.dst_ip = hdr_ips[1]
   end
   self.protocol = b[IPV6_NEXT_HEADER_OFFSET]
   if self.protocol == IP_TCP or self.protocol == IP_UDP then
      local hdr_ports = ffi.cast('uint16_t*', b+IPV6_SOURCE_PORT_OFFSET)
      self.src_port = hdr_ports[0]
      self.dst_port = hdr_ports[1]
   else
      self.src_port, self.dst_port = 0, 0
   end
   return self
end


do
   local s2 = nil
   function ipv6:track(trackname)
      s2 = s2 or spec_v6()
      return conntrack.track(trackname, self:__tostring(), self:reverse(s2):__tostring())
   end
end


spec_v6 = ffi.metatype(spec_v6, ipv6)

------

local new_spec=nil
do
   local specv4 = spec_v4()
   local specv6 = spec_v6()
   new_spec = function (b)
      if not b then return nil end
      local ethertype = ffi.cast('uint16_t*', b+ETHERTYPE_OFFSET)[0]
      if ethertype == ETHERTYPE_IPV4 then
         return specv4:fill(b)
      end
      if ethertype == ETHERTYPE_IPV6 then
         return specv6:fill(b)
      end
   end
end

return {
   define = conntrack.define,
   spec = new_spec,
   age = conntrack.age,
   clear = conntrack.clear,
}

