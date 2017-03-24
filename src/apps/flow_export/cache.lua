-- This module implements the FlowCache class, which is used to track
-- flow keys & flow records for IPFIX flow metering and exporting.

module(..., package.seeall)

local ffi    = require("ffi")
local ctable = require("lib.ctable")

-- Flow key & flow record FFI type definitions
--
-- see https://www.iana.org/assignments/ipfix/ipfix.xhtml for
-- information on the IEs for the flow key and record
ffi.cdef[[
   struct flow_key {
      uint32_t src_ipv4;    /* sourceIPv4Address */
      uint32_t dst_ipv4;    /* destinationIPv4Address */
      uint32_t src_ipv6_1;  /* sourceIPv6Address */
      uint32_t src_ipv6_2;
      uint32_t src_ipv6_3;
      uint32_t src_ipv6_4;
      uint32_t dst_ipv6_1;  /* destinationIPv6Address */
      uint32_t dst_ipv6_2;
      uint32_t dst_ipv6_3;
      uint32_t dst_ipv6_4;
      uint8_t is_ipv6;
      uint8_t protocol;     /* protocolIdentifier */
      uint16_t src_port;    /* sourceTransportPort */
      uint16_t dst_port;    /* destinationTransportPort */
      uint16_t __padding;
   } __attribute__((packed));

   struct flow_record {
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
      uint8_t __padding;
   } __attribute__((packed));
]]

FlowCache = {}

function FlowCache:new(config)
   assert(config, "expected configuration table")

   local o = { -- TODO: compute the default cache value
               --       based on expected flow amounts?
               cache_size = config.cache_size or 20000 }

   local params = {
      key_type = ffi.typeof("struct flow_key"),
      value_type = ffi.typeof("struct flow_record"),
      max_occupancy_rate = 0.4,
      initial_size = math.ceil(o.cache_size / 0.4),
   }

   o.table = ctable.new(params)

   return setmetatable(o, { __index = self })
end

function FlowCache:add(flow_key, flow_record)
   self.table:add(flow_key, flow_record)
end

function FlowCache:lookup(flow_key)
   return self.table:lookup_ptr(flow_key)
end

function FlowCache:iterate()
   return self.table:iterate()
end

function FlowCache:remove(flow_key)
   self.table:remove(flow_key)
end
