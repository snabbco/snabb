module(..., package.seeall)

local ffi = require("ffi")

local ethernet_header_type = ffi.typeof([[
   struct {
      uint8_t  ether_dhost[6];
      uint8_t  ether_shost[6];
      uint16_t ether_type;
   }
]])

ethernet_header_ptr_type = ffi.typeof("$*", ethernet_header_type)

local ipv6_ptr_type = ffi.typeof([[
   struct {
      uint32_t v_tc_fl; // version, tc, flow_label
      uint16_t payload_length;
      uint8_t  next_header;
      uint8_t  hop_limit;
      uint8_t  src_ip[16];
      uint8_t  dst_ip[16];
   } __attribute__((packed))
]])

ipv6_header_ptr_type = ffi.typeof("$*", ipv6_ptr_type)
