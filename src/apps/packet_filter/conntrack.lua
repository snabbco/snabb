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

local conn_spec_ipv4 = ffi.typeof 'conn_spec_ipv4'


local function conn_spec_from_ipv4_header(b)
   local spec = conn_spec_ipv4()
   local flags = 0
   do
      local hdr_ips = ffi.cast('uint32_t*', b+IPV4_SOURCE_OFFSET)
      spec.src_ip = hdr_ips[0]
      spec.dst_ip = hdr_ips[1]
   end
   spec.protocol = b[IPV4_PROTOCOL_OFFSET]
   if spec.protocol == IP_TCP or spec.protocol == IP_UDP then
      local hdr_ports = ffi.cast('uint16_t*', b+IPV4_SOURCE_PORT_OFFSET)
      spec.src_port = hdr_ports[0]
      spec.dst_port = hdr_ports[1]
      if spec.protocol == IP_TCP then
         flags = b[IPV4_TCP_FLAGS]
      end
   else
      spec.src_port, spec.dst_port = 0, 0
   end
   return spec, flags
end


local conn_spec_ipv6 = ffi.typeof 'conn_spec_ipv6'

local function conn_spec_from_ipv6_header(b)
   local spec = conn_spec_ipv6()
   local flags = 0
   do
      local hdr_ips = ffi.cast('ipv6_addr*', b+IPV6_SOURCE_OFFSET)
      spec.src_ip = hdr_ips[0]
      spec.dst_ip = hdr_ips[1]
   end
   spec.protocol = b[IPV6_NEXT_HEADER_OFFSET]
   if spec.protocol == IP_TCP or spec.protocol == IP_UDP then
      local hdr_ports = ffi.cast('uint16_t*', b+IPV6_SOURCE_PORT_OFFSET)
      spec.src_port = hdr_ports[0]
      spec.dst_port = hdr_ports[1]
      if spec.protocol == IP_TCP then
         flags = b[IPV6_TCP_FLAGS]
      end
   else
      spec.src_port, spec.dst_port = 0, 0
   end
   return spec, flags
end


-- Return an FFI struct containing the session ID for a buffer
-- containing packet data.
--
-- Returns nil if the session cannot be determined due to an
-- unsupported protocol.
local function spec_from_header(b)
   local ethertype = ffi.cast('uint16_t*', b+ETHERTYPE_OFFSET)[0]
   if ethertype == ETHERTYPE_IPV4 then
      return conn_spec_from_ipv4_header(b)
   end
   if ethertype == ETHERTYPE_IPV6 then
      return conn_spec_from_ipv6_header(b)
   end
end


-- reverses a conntrack spec in-site
local function reverse_spec(spec)
   if ffi.istype(conn_spec_ipv6, spec) then
      spec.src_ip.a, spec.dst_ip.a = spec.dst_ip.a, spec.src_ip.a
      spec.src_ip.b, spec.dst_ip.b = spec.dst_ip.b, spec.src_ip.b
   else
      spec.src_ip, spec.dst_ip = spec.dst_ip, spec.src_ip
   end
   spec.src_port, spec.dst_port = spec.dst_port, spec.src_port
   return spec
end

local function spec_tostring(spec)
   return ffi.string(spec, ffi.sizeof(spec))
end


-- show a spec from a binary string
local function dump_from_string(k, v)
   local ptr = ffi.cast('char *', k)
   local af_inet, strmaxlen = 0, 0
   local spec = nil, nil

   if #k == ffi.sizeof(conn_spec_ipv6) then
      af_inet, strmaxlen = 10, 46
      spec = conn_spec_ipv6()

   elseif #k == ffi.sizeof(conn_spec_ipv4) then
      af_inet, strmaxlen = 2, 16
      spec = conn_spec_ipv4()
   end

   local function ip_tostring (offset)
      local buf = ffi.new('char[?]', strmaxlen)
      local r = ffi.C.inet_ntop(af_inet, ptr+offset, buf, strmaxlen)
      if r == nil then return nil end
      return ffi.string(buf)
   end

   ffi.copy(spec, k, ffi.sizeof(spec))
   return string.format(
      '[%d/%X] %s/%d - %s/%d',
      spec.protocol, v,
      ip_tostring(ffi.offsetof(spec, 'src_ip')), lib.ntohs(spec.src_port),
      ip_tostring(ffi.offsetof(spec, 'dst_ip')), lib.ntohs(spec.dst_port))
end

---
--- named connection track tables
---

-- conntracks is the global named directory of connection track tables.
-- each track table is a three-element Lua array, 'p' in these functions.
-- p[1] is the 'current' set of connections.  all new tracks go there.
-- p[2] is the 'previous' set of connections. a connection is considered
--      active if it's on either the current or previous set.
-- p[3] is the next expiration time. after that time, the age() function
--      expires all connections on p[2] but not on p[1] when time p[3]

local conntracks = {}
local time = engine.now
local function new(t) return {{}, {}, (time() or 0)+t} end
local function put(p, k, v) p[1][k] = v end
local function get(p, k) return p[1][k] or p[2][k] end
local function age(p, t)
   if time() > p[3] then
      p[1], p[2], p[3] = {}, p[1], time()+t
   end
end

return {
   define = function (name, agestep)
      conntracks[name] = conntracks[name] or new(agestep or 7200)
   end,

   track = function (name, buffer)
      local p = conntracks[name]
      local spec, flags = spec_from_header(buffer)
      if spec then
	 put(p, spec_tostring(spec), flags)
	 reverse_spec(spec)
	 put(p, spec_tostring(spec), flags)
      end
   end,

   check = function (name, buffer)
      local spec = spec_from_header(buffer)
      return spec and get(conntracks[name], spec_tostring(spec))
   end,

   age = age,

   clear = function ()
      for name, p in pairs(conntracks) do
         p[1], p[2], p[3] = {}, {}, time()+7200
      end
      conntracks = {}
   end,

   ageall = function ()
      for name, p in pairs(conntracks) do
         age(p, 7200)
      end
   end,

   dump = function ()
      for name, p in pairs(conntracks) do
         print (string.format('---- %s -----', name))
         local rem_time = p[3] - time()
         print ('current connections')
         for k,v in pairs(p[1]) do
            print (dump_from_string(k, v))
         end
         print (string.format('to expire in %g seconds', rem_time))
         for k,v in pairs(p[2]) do
            if not p[1][k] then
               print (dump_from_string(k))
            end
         end
         print ('-----------')
      end
   end,
}
