-- conntrack.lua -- Connection tracking for IPv4/IPv6 TCP/UDP sessions
--
-- This module exposes the following API:
--
--  define(tablename)
--    define a named connection tracking table.
--
--  clear()
--    clears all tracking tables.
--
--  spec(buffer)
--    returns a spec object, encapsulating the connection
--    specifications if the packet in `buffer`.
--
--  spec:track(trackname)
--    tracks the connection in the named tracking table.
--    internally handles any ageing and table rotation.
--
--  spec:check(trackname)
--    checks if an equivalent (or revese) spec is registered
--    in the named tracking table.
--
--  NOTE: the spec() function doesn't allocate new spec objects,
--  the returned objects are to be used and for tracking and
--  checking but not stored, because they might be overwritten
--  by the next call to spec().


local ffi = require 'ffi'
local lib = require 'core.lib'

local const = ffi.new([[struct {
   static const int ETHERTYPE_IPV4 = 0x0008;
   static const int ETHERTYPE_IPV6 = 0xDD86;

   static const int IP_UDP = 0x11;
   static const int IP_TCP = 6;

   static const int ETHERTYPE_OFFSET = 12;

   static const int IPV4_SOURCE_OFFSET = 26;
   static const int IPV4_PROTOCOL_OFFSET = 23;
   static const int IPV4_SOURCE_PORT_OFFSET = 34;

   static const int IPV6_SOURCE_OFFSET = 22;
   static const int IPV6_NEXT_HEADER_OFFSET = 20; // protocol
   static const int IPV6_SOURCE_PORT_OFFSET = 54;
}]])

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

---
--- connection tracking
---
--- these are the only functions that have access
--- to the connection tracking tables.
---
local define, track, check, clear
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

   function define (name)
      if not name then return end
      conntracks[name] = conntracks[name] or new()
      counts[name] = counts[name] or 0
   end

   function track (name, key, revkey, limit)
      limit = limit or 1000
      local p = conntracks[name]
      if age(p, 7200) or counts[name] > limit and age(p, 0.01) then
         counts[name] = 0
      end

      if put(p, key, true) then
         counts[name] = counts[name] + 1
      end
      put(p, revkey, true)
   end

   function check (name, key)
      return key and get(conntracks[name], key)
   end

   function clear()
      for name, p in pairs(conntracks) do
         p[1], p[2], p[3] = {}, {}, time()
      end
      conntracks = {}
   end
end

-----------------
--- generic connection spec functions, work for either IPv4 or IPv6
local genspec = {}

--- reverses a spec
--- o: (optional) if given, a spec to be filled with
--- the reverse of the original
--- if omitted, the spec is reversed in place.
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

--- returns a binary string, usable as a table key
function genspec:__tostring()
   return ffi.string(self, ffi.sizeof(self))
end

--- checks if the spec is present in the named tracking table
function genspec:check(trackname)
   return check(trackname, self:__tostring())
end


----
--- IPv4 spec

local spec_v4 = ffi.typeof('conn_spec_ipv4')
local ipv4 = {
   __tostring  = genspec.__tostring,
   reverse = genspec.reverse,
   check = genspec.check
}
ipv4.__index = ipv4


--- fills `self` with the specifications of
--- the packet in `b` (a byte buffer)
function ipv4:fill(b)
   do
      local hdr_ips = ffi.cast('uint32_t*', b+const.IPV4_SOURCE_OFFSET)
      self.src_ip = hdr_ips[0]
      self.dst_ip = hdr_ips[1]
   end
   self.protocol = b[const.IPV4_PROTOCOL_OFFSET]
   if self.protocol == const.IP_TCP or self.protocol == const.IP_UDP then
      local hdr_ports = ffi.cast('uint16_t*', b+const.IPV4_SOURCE_PORT_OFFSET)
      self.src_port = hdr_ports[0]
      self.dst_port = hdr_ports[1]
   else
      self.src_port, self.dst_port = 0, 0
   end
   return self
end

--- inserts `self` in the named tracking table.
--- it's iserted twice: directly and reversed
do
   local rev = nil      -- to hold the reversed spec
   function ipv4:track(trackname)
      rev = rev or spec_v4()
      return track(trackname, self:__tostring(), self:reverse(rev):__tostring())
   end
end

spec_v4 = ffi.metatype(spec_v4, ipv4)


-------
--- IPv6 spec

local spec_v6 = ffi.typeof('conn_spec_ipv6')
local ipv6 = {
   __tostring  = genspec.__tostring,
   reverse = genspec.reverse,
   check = genspec.check
}
ipv6.__index = ipv6


--- fills `self` with the specifications of
--- the packet in `b` (a byte buffer)
function ipv6:fill(b)
   do
      local hdr_ips = ffi.cast('ipv6_addr*', b+const.IPV6_SOURCE_OFFSET)
      self.src_ip = hdr_ips[0]
      self.dst_ip = hdr_ips[1]
   end
   self.protocol = b[const.IPV6_NEXT_HEADER_OFFSET]
   if self.protocol == const.IP_TCP or self.protocol == const.IP_UDP then
      local hdr_ports = ffi.cast('uint16_t*', b+const.IPV6_SOURCE_PORT_OFFSET)
      self.src_port = hdr_ports[0]
      self.dst_port = hdr_ports[1]
   else
      self.src_port, self.dst_port = 0, 0
   end
   return self
end


--- inserts `self` in the named tracking table.
--- it's iserted twice: directly and reversed
do
   local rev = nil
   function ipv6:track(trackname)
      rev = rev or spec_v6()
      return track(trackname, self:__tostring(), self:reverse(rev):__tostring())
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
      local ethertype = ffi.cast('uint16_t*', b+const.ETHERTYPE_OFFSET)[0]
      if ethertype == const.ETHERTYPE_IPV4 then
         return specv4:fill(b)
      end
      if ethertype == const.ETHERTYPE_IPV6 then
         return specv6:fill(b)
      end
   end
end

return {
   define = define,
   spec = new_spec,
   clear = clear,
}

