-- This module implements the FlowCache class, which is used to track
-- flow keys & flow records for IPFIX flow metering and exporting.

module(..., package.seeall)

local bit    = require("bit")
local ffi    = require("ffi")
local ctable = require("lib.ctable")

-- Flow key & flow record FFI type definitions
--
-- see https://www.iana.org/assignments/ipfix/ipfix.xhtml for
-- information on the IEs for the flow key and record
--
local ipv4_flow_key_t = ffi.typeof[[
   struct {
      uint8_t src_ip[4];    /* sourceIPv4Address */
      uint8_t dst_ip[4];    /* destinationIPv4Address */
      uint8_t protocol;     /* protocolIdentifier */
      uint16_t src_port;    /* sourceTransportPort */
      uint16_t dst_port;    /* destinationTransportPort */
   } __attribute__((packed))
]]

local ipv6_flow_key_t = ffi.typeof[[
   struct {
      uint8_t src_ip[16];   /* sourceIPv6Address */
      uint8_t dst_ip[16];   /* destinationIPv6Address */
      uint8_t protocol;     /* protocolIdentifier */
      uint16_t src_port;    /* sourceTransportPort */
      uint16_t dst_port;    /* destinationTransportPort */
   } __attribute__((packed))
]]

local flow_record_t = ffi.typeof[[
   struct {
      uint64_t start_time;  /* flowStartMilliseconds */
      uint64_t end_time;    /* flowEndMilliseconds */
      uint64_t pkt_count;   /* packetDeltaCount */
      uint64_t octet_count; /* octetDeltaCount */
      uint32_t ingress;     /* ingressInterface */
      uint32_t egress;      /* egressInterface */
      uint32_t src_peer_as; /* bgpPrevAdjacentAsNumber */
      uint32_t dst_peer_as; /* bgpNextAdjacentAsNumber */
      uint16_t tcp_control; /* tcpControlBits */
      uint8_t tos;          /* ipClassOfService */
   } __attribute__((packed))
]]

local Cache = {}

function Cache:new(config, key_t)
   assert(config, "expected configuration table")

   local o = { -- TODO: compute the default cache value
               --       based on expected flow amounts?
               cache_size = config.cache_size or 20000,
               -- expired flows go into this array
               -- TODO: perhaps a ring buffer is a better idea here
               expired = {} }

   -- how much of the cache to traverse when iterating
   o.stride = math.ceil(o.cache_size / 1000)

   local params = {
      key_type = key_t,
      value_type = flow_record_t,
      max_occupancy_rate = 0.4,
      initial_size = math.ceil(o.cache_size / 0.4),
   }

   o.preallocated_key = key_t()
   o.preallocated_value = flow_record_t()
   o.table = ctable.new(params)

   return setmetatable(o, { __index = self })
end

function Cache:iterate()
   -- use the underlying ctable's iterator, but restrict the max stride
   -- for each use of the iterator
   local next_entry = self.next_entry or self.table:iterate()
   local last_entry = self.last_entry or self.table.entries - 1
   local max_entry  = last_entry + self.stride
   local table_max  =
      self.table.entries + self.table.size + self.table.max_displacement

   if table_max < max_entry then
      max_entry = table_max
      self.last_entry = nil
   else
      self.last_entry = max_entry
   end

   return next_entry, max_entry, last_entry
end

function Cache:remove(flow_key)
   self.table:remove(flow_key)
end

function Cache:expire_record(key, record, active)
   -- for active expiry, we keep the record around in the cache
   -- so we need a copy that won't be modified
   if active then
      local copied_record = ffi.new("struct flow_record")
      ffi.copy(copied_record, record, ffi.sizeof("struct flow_record"))
      table.insert(self.expired, {key = key, value = copied_record})
   else
      table.insert(self.expired, {key = key, value = record})
   end
end

function Cache:get_expired()
   local ret = self.expired
   self.expired = {}
   return ret
end

FlowCache = {}

function FlowCache:new(config)
   assert(config, "expected configuration table")
   local o = {}
   o.v4 = Cache:new(config, ipv4_flow_key_t)
   o.v6 = Cache:new(config, ipv6_flow_key_t)
   return setmetatable(o, { __index = self })
end
