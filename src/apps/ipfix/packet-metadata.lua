module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local consts   = require("apps.lwaftr.constants")

local ntohs  = lib.ntohs
local htons = lib.htons

local ethertype_ipv4         = consts.ethertype_ipv4
local ethertype_ipv6         = consts.ethertype_ipv6
local ethernet_header_size   = consts.ethernet_header_size
local o_ipv4_total_length    = consts.o_ipv4_total_length
local o_ipv4_ver_and_ihl     = consts.o_ipv4_ver_and_ihl
local o_ipv4_flags           = consts.o_ipv4_flags
local o_ipv4_proto           = consts.o_ipv4_proto
local ipv6_fixed_header_size = consts.ipv6_fixed_header_size
local o_ipv6_payload_len     = consts.o_ipv6_payload_len
local o_ipv6_next_header     = consts.o_ipv6_next_header

local uint16_ptr_t = ffi.typeof('uint16_t *')

local function get_ipv4_total_length(l3)
   return ntohs(ffi.cast(uint16_ptr_t, l3 + o_ipv4_total_length)[0])
end

local function get_ipv4_ihl(l3)
   return (bit.band((l3 + o_ipv4_ver_and_ihl)[0], 0x0f))
end

local function get_ipv4_offset(l3)
   local flags_offset = ntohs(ffi.cast(uint16_ptr_t, l3 + o_ipv4_flags)[0])
   return (bit.band(0x1fff, flags_offset))
end

local function get_ipv4_protocol(l3)    return l3[o_ipv4_proto] end

local function get_ipv6_payload_length(l3)
   return ntohs(ffi.cast(uint16_ptr_t, l3 + o_ipv6_payload_len)[0])
end
local function set_ipv6_payload_length(l3, length)
   (ffi.cast(uint16_ptr_t, l3 + o_ipv6_payload_len))[0] = htons(length)
end

local function get_ipv6_next_header(l3) return l3[o_ipv6_next_header] end
local function set_ipv6_next_header(l3, type) l3[o_ipv6_next_header] = type end

local function ptr_to(ctype) return ffi.typeof('$*', ctype) end

local ipv6_ext_hdr_t = ffi.typeof([[
   struct {
      uint8_t next_header;
      uint8_t length;
      uint8_t  data[0];
   }  __attribute__((packed))
]])
local ipv6_ext_hdr_ptr_t = ptr_to(ipv6_ext_hdr_t)

local ipv6_frag_hdr_t = ffi.typeof([[
   struct {
      uint8_t next_header;
      uint8_t reserved;
      uint16_t offset_flags;
      uint32_t identificaton;
   }  __attribute__((packed))
]])
local ipv6_frag_hdr_ptr_t = ptr_to(ipv6_frag_hdr_t)

local function ipv6_generic_ext_hdr(ptr)
   local ext_hdr = ffi.cast(ipv6_ext_hdr_ptr_t, ptr)
   local next_header = ext_hdr.next_header
   local length = ext_hdr.length
   -- Length in unit of 8 byets, does not include the first 8 bytes
   return length * 8 + 8, next_header
end

-- The fragmentation header inspector sets this upvalue as a side
-- effect.  Only at most one fragmentation header is expected in a
-- header chain.
local ipv6_frag_offset

local ipv6_ext_hdr_fns = {
   [0] =
      -- Hop-by-hop
      ipv6_generic_ext_hdr,
   [43] =
      -- Routing
      ipv6_generic_ext_hdr,
   [44] =
      -- Fragmentation, fixed size (8 bytes)
      function(ptr)
         local frag_hdr = ffi.cast(ipv6_frag_hdr_ptr_t, ptr)
         local next_header = frag_hdr.next_header
         ipv6_frag_offset = bit.rshift(ntohs(frag_hdr.offset_flags), 3)
         return 8, next_header
      end,
   [51] =
      -- IPSec authentication header RFC4302
      function(ptr)
         local ext_hdr = ffi.cast(ipv6_ext_hdr_ptr_t, ptr)
         local next_header = ext_hdr.next_header
         -- Length of the header in units of 4 bytes minus 2
         local payload_len = ext_hdr.length
         return payload_len * 4 - 2, next_header
      end,
   [59] =
      -- No next header
      function(ptr)
         return 0, 255
      end,
   [60] =
      -- Destination
      ipv6_generic_ext_hdr,
   [135] =
      -- Mobility RFC6275
      ipv6_generic_ext_hdr,
   [139] =
      -- HIP RFC7401
      ipv6_generic_ext_hdr,
   [140] =
      -- Shim6 RFC5533
      ipv6_generic_ext_hdr,
}

function squash_extension_headers(pkt, l3)
   local payload = l3 + ipv6_fixed_header_size
   local payload_length = get_ipv6_payload_length(l3)
   local ulp = get_ipv6_next_header(l3)

   local next_header = ulp
   local ext_hdrs_size = 0
   ipv6_frag_offset = 0
   local ipv6_ext_hdr_fn = ipv6_ext_hdr_fns[next_header]
   while ipv6_ext_hdr_fn do
      hdr_size, next_header = ipv6_ext_hdr_fn(payload + ext_hdrs_size)
      ext_hdrs_size = ext_hdrs_size + hdr_size
      if ext_hdrs_size < 0 or ext_hdrs_size > pkt.length then
         -- The extension header has lead us out of the packet, bail
         -- out and leave the packet unmodified
         goto exit
      end
      ipv6_ext_hdr_fn = ipv6_ext_hdr_fns[next_header]
   end
   -- All extension headers known to us have been skipped. next_header
   -- contains what we consider as the "upper layer protocol".
   if ext_hdrs_size > 0 then
      pkt.length = pkt.length - ext_hdrs_size
      payload_length = payload_length - ext_hdrs_size
      ulp = next_header
      set_ipv6_next_header(l3, ulp)
      set_ipv6_payload_length(l3, payload_length)
      ffi.C.memmove(payload, payload + ext_hdrs_size,
                    payload_length + ffi.sizeof(pkt_meta_data_t))
   end
   ::exit::
   return payload_length, ulp
end

ether_header_t = ffi.typeof([[
   struct {
      uint8_t dhost[6];
      uint8_t shost[6];
      union {
         struct {
            uint16_t type;
         } ether;
         struct {
            uint16_t tpid;
            uint16_t tci;
            uint16_t type;
         } dot1q;
      };
   } __attribute__((packed))
]])
ether_header_ptr_t = ptr_to(ether_header_t)

local magic_number = 0x5ABB

pkt_meta_data_t = ffi.typeof([[
   struct {
      uint16_t magic;
      /* Actual ethertype for single-tagged frames */
      uint16_t ethertype;
      /* vlan == 0 if untagged frame */
      uint16_t vlan;
      /* Total size, excluding the L2 header */
      uint16_t total_length;
      /* Pointer and length that can be passed directly to a pflua filter */
      uint8_t *filter_start;
      uint16_t filter_length;
      /* Pointers to the L3 and L4 headers */
      uint8_t *l3;
      uint8_t *l4;
      uint8_t proto;
      /* Fragment offset in units of 8 bytes.  Equals 0 if not fragmented
         or initial fragment */
      uint8_t frag_offset;
      /* Difference between packet length and length
         according to the l3 header, negative if the
         packet is truncated, == 0 if not. A positive value
         would indicate that the packet contains some kind
         of padding.  This should not occur under normal
         circumstances. */
      int16_t length_delta;
   } __attribute__((packed))
]])
pkt_meta_data_ptr_t = ptr_to(pkt_meta_data_t)

function get (pkt)
   local md = ffi.cast(pkt_meta_data_ptr_t, pkt.data + pkt.length)
   assert(md.magic == magic_number)
   return md
end

function add (pkt)
   local vlan = 0
   local filter_offset = 0
   local l3_offset = ethernet_header_size
   local hdr = ffi.cast(ether_header_ptr_t, pkt.data)
   local ethertype = lib.ntohs(hdr.ether.type)
   if ethertype == 0x8100 then
      ethertype = lib.ntohs(hdr.dot1q.type)
      vlan = bit.band(lib.ntohs(hdr.dot1q.tci), 0xFFF)
      filter_offset = 4
      l3_offset = l3_offset + filter_offset
   end

   local md = ffi.cast(pkt_meta_data_ptr_t, pkt.data + pkt.length)
   md.magic = magic_number
   md.ethertype = ethertype
   md.vlan = vlan
   md.filter_start = pkt.data + filter_offset
   md.filter_length = pkt.length - filter_offset
   local l3 = pkt.data + l3_offset
   md.l3 = l3

   if ethertype == ethertype_ipv4 then
      md.total_length = get_ipv4_total_length(l3)
      md.l4 = l3 + 4 * get_ipv4_ihl(l3)
      md.frag_offset = get_ipv4_offset(l3)
      md.proto = get_ipv4_protocol(l3)
   elseif ethertype == ethertype_ipv6 then
      --Remove all extension headers from the packet and track the
      --position of the metadata block
      local payload_length, next_header =
         squash_extension_headers(pkt, l3)
      md = get(pkt)
      md.total_length = payload_length + ipv6_fixed_header_size
      md.l4 = l3 + ipv6_fixed_header_size
      md.frag_offset = ipv6_frag_offset
      md.proto = next_header
   end

   md.length_delta = pkt.length - l3_offset - md.total_length
   return md
end
