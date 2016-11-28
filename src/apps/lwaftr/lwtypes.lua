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
ethernet_header_size = ffi.sizeof(ethernet_header_type)

local ethernet_vlan_header_type = ffi.typeof([[
   struct {
      uint8_t  ether_dhost[6];
      uint8_t  ether_shost[6];
      struct {
         uint16_t tpid;
         uint16_t tag;
      } vlan;
      uint16_t ether_type;
   }
]])
ethernet_vlan_header_ptr_type = ffi.typeof("$*", ethernet_vlan_header_type)
ethernet_vlan_header_size = ffi.sizeof(ethernet_vlan_header_type)

local ipv4hdr_t = ffi.typeof[[
struct {
  uint16_t ihl_v_tos; // ihl:4, version:4, tos(dscp:6 + ecn:2)
  uint16_t total_length;
  uint16_t id;
  uint16_t frag_off; // flags:3, fragmen_offset:13
  uint8_t  ttl;
  uint8_t  protocol;
  uint16_t checksum;
  uint8_t  src_ip[4];
  uint8_t  dst_ip[4];
} __attribute__((packed))
]]
ipv4_header_ptr_type = ffi.typeof("$*", ipv4hdr_t)
ipv4_header_size = ffi.sizeof(ipv4hdr_t)

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
ipv6_header_size = ffi.sizeof(ipv6_ptr_type)

local udp_header_t = ffi.typeof[[
struct {
  uint16_t    src_port;
  uint16_t    dst_port;
  uint16_t    len;
  uint16_t    checksum;
} __attribute__((packed))
]]
udp_header_ptr_type = ffi.typeof("$*", udp_header_t)
udp_header_size = ffi.sizeof(udp_header_t)

lwaftr_id_type = ffi.typeof[[
struct {
  char value[256];
}
]]
