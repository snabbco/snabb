module(..., package.seeall)

local bt = require("apps.lwaftr.binding_table")
local constants = require("apps.lwaftr.constants")
local lwdebug = require("apps.lwaftr.lwdebug")
local lwutil = require("apps.lwaftr.lwutil")

local checksum = require("lib.checksum")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local counter = require("core.counter")
local packet = require("core.packet")
local lib = require("core.lib")
local link = require("core.link")
local engine = require("core.app")
local bit = require("bit")
local ffi = require("ffi")
local alarms = require("lib.yang.alarms")

local CounterAlarm = alarms.CounterAlarm
local band, bnot = bit.band, bit.bnot
local rshift, lshift = bit.rshift, bit.lshift
local receive, transmit = link.receive, link.transmit
local rd16, wr16, rd32, wr32 = lwutil.rd16, lwutil.wr16, lwutil.rd32, lwutil.wr32
local ipv6_equals = lwutil.ipv6_equals
local is_ipv4, is_ipv6 = lwutil.is_ipv4, lwutil.is_ipv6
local htons, ntohs, ntohl = lib.htons, lib.ntohs, lib.ntohl
local is_ipv4_fragment, is_ipv6_fragment = lwutil.is_ipv4_fragment, lwutil.is_ipv6_fragment

local S = require("syscall")

-- Note whether an IPv4 packet is actually coming from the internet, or from
-- a b4 and hairpinned to be re-encapsulated in another IPv6 packet.
local PKT_FROM_INET = 1
local PKT_HAIRPINNED = 2

local debug = lib.getenv("LWAFTR_DEBUG")

local ethernet_header_t = ffi.typeof([[
   struct {
      uint8_t  dhost[6];
      uint8_t  shost[6];
      uint16_t type;
      uint8_t  payload[0];
   }
]])
local ipv4_header_t = ffi.typeof [[
   struct {
      uint8_t version_and_ihl;       // version:4, ihl:4
      uint8_t dscp_and_ecn;          // dscp:6, ecn:2
      uint16_t total_length;
      uint16_t id;
      uint16_t flags_and_fragment_offset;  // flags:3, fragment_offset:13
      uint8_t  ttl;
      uint8_t  protocol;
      uint16_t checksum;
      uint8_t  src_ip[4];
      uint8_t  dst_ip[4];
   } __attribute__((packed))
]]
local ipv6_header_t = ffi.typeof([[
   struct {
      uint32_t v_tc_fl;             // version:4, traffic class:8, flow label:20
      uint16_t payload_length;
      uint8_t  next_header;
      uint8_t  hop_limit;
      uint8_t  src_ip[16];
      uint8_t  dst_ip[16];
   } __attribute__((packed))
]])
local ipv6_pseudo_header_t = ffi.typeof[[
struct {
   char src_ip[16];
   char dst_ip[16];
   uint32_t payload_length;
   uint32_t next_header;
} __attribute__((packed))
]]
local icmp_header_t = ffi.typeof [[
struct {
   uint8_t type;
   uint8_t code;
   int16_t checksum;
} __attribute__((packed))
]]

local ethernet_header_ptr_t = ffi.typeof("$*", ethernet_header_t)
local ethernet_header_size = ffi.sizeof(ethernet_header_t)

local ipv4_header_ptr_t = ffi.typeof("$*", ipv4_header_t)
local ipv4_header_size = ffi.sizeof(ipv4_header_t)

local ipv6_header_ptr_t = ffi.typeof("$*", ipv6_header_t)
local ipv6_header_size = ffi.sizeof(ipv6_header_t)

local ipv6_header_ptr_t = ffi.typeof("$*", ipv6_header_t)
local ipv6_header_size = ffi.sizeof(ipv6_header_t)

local icmp_header_t = ffi.typeof("$*", icmp_header_t)
local icmp_header_size = ffi.sizeof(icmp_header_t)

local ipv6_pseudo_header_size = ffi.sizeof(ipv6_pseudo_header_t)

-- Local bindings for constants that are used in the hot path of the
-- data plane.  Not having them here is a 1-2% performance penalty.
local n_ethertype_ipv4 = constants.n_ethertype_ipv4
local n_ethertype_ipv6 = constants.n_ethertype_ipv6

local function get_ethernet_payload(pkt)
   return pkt.data + ethernet_header_size
end
local function get_ethernet_payload_length(pkt)
   return pkt.length - ethernet_header_size
end

local o_ipv4_checksum = constants.o_ipv4_checksum
local o_ipv4_dscp_and_ecn = constants.o_ipv4_dscp_and_ecn
local o_ipv4_dst_addr = constants.o_ipv4_dst_addr
local o_ipv4_flags = constants.o_ipv4_flags
local o_ipv4_proto = constants.o_ipv4_proto
local o_ipv4_src_addr = constants.o_ipv4_src_addr
local o_ipv4_total_length = constants.o_ipv4_total_length
local o_ipv4_ttl = constants.o_ipv4_ttl

local function get_ipv4_header_length(ptr)
   local ver_and_ihl = ptr[0]
   return lshift(band(ver_and_ihl, 0xf), 2)
end
local function get_ipv4_total_length(ptr)
   return ntohs(rd16(ptr + o_ipv4_total_length))
end
local function get_ipv4_src_address_ptr(ptr)
   return ptr + o_ipv4_src_addr
end
local function get_ipv4_dst_address_ptr(ptr)
   return ptr + o_ipv4_dst_addr
end
local function get_ipv4_src_address(ptr)
   return ntohl(rd32(get_ipv4_src_address_ptr(ptr)))
end
local function get_ipv4_dst_address(ptr)
   return ntohl(rd32(get_ipv4_dst_address_ptr(ptr)))
end
local function get_ipv4_proto(ptr)
   return ptr[o_ipv4_proto]
end
local function get_ipv4_flags(ptr)
   return ptr[o_ipv4_flags]
end
local function get_ipv4_dscp_and_ecn(ptr)
   return ptr[o_ipv4_dscp_and_ecn]
end
local function get_ipv4_payload(ptr)
   return ptr + get_ipv4_header_length(ptr)
end
local function get_ipv4_payload_src_port(ptr)
   -- Assumes that the packet is TCP or UDP.
   return ntohs(rd16(get_ipv4_payload(ptr)))
end
local function get_ipv4_payload_dst_port(ptr)
   -- Assumes that the packet is TCP or UDP.
   return ntohs(rd16(get_ipv4_payload(ptr) + 2))
end

local ipv6_fixed_header_size = constants.ipv6_fixed_header_size
local o_ipv6_dst_addr = constants.o_ipv6_dst_addr
local o_ipv6_next_header = constants.o_ipv6_next_header
local o_ipv6_src_addr = constants.o_ipv6_src_addr

local function get_ipv6_src_address(ptr)
   return ptr + o_ipv6_src_addr
end
local function get_ipv6_dst_address(ptr)
   return ptr + o_ipv6_dst_addr
end
local function get_ipv6_next_header(ptr)
   return ptr[o_ipv6_next_header]
end
local function get_ipv6_payload(ptr)
   -- FIXME: Deal with multiple IPv6 headers?
   return ptr + ipv6_fixed_header_size
end

local proto_icmp = constants.proto_icmp
local proto_icmpv6 = constants.proto_icmpv6
local proto_ipv4 = constants.proto_ipv4

local function get_icmp_type(ptr)
   return ptr[0]
end
local function get_icmp_code(ptr)
   return ptr[1]
end
local function get_icmpv4_echo_identifier(ptr)
   return ntohs(rd16(ptr + constants.o_icmpv4_echo_identifier))
end
local function get_icmp_mtu(ptr)
   local next_hop_mtu_offset = 6
   return ntohs(rd16(ptr + next_hop_mtu_offset))
end
local function get_icmp_payload(ptr)
   return ptr + constants.icmp_base_size
end

local function write_ethernet_header(pkt, ether_type)
   local h = ffi.cast(ethernet_header_ptr_t, pkt.data)
   ffi.fill(h.shost, 6, 0)
   ffi.fill(h.dhost, 6, 0)
   h.type = ether_type
end

local function prepend_ethernet_header(pkt, ether_type)
   pkt = packet.shiftright(pkt, ethernet_header_size)
   write_ethernet_header(pkt, ether_type)
   return pkt
end

local function write_ipv6_header(ptr, src, dst, tc, flow_label, next_header, payload_length)
   local h = ffi.cast(ipv6_header_ptr_t, ptr)
   h.v_tc_fl = 0
   lib.bitfield(32, h, 'v_tc_fl', 0, 4, 6)   -- IPv6 Version
   lib.bitfield(32, h, 'v_tc_fl', 4, 8, tc)  -- Traffic class
   lib.bitfield(32, h, 'v_tc_fl', 12, 20, flow_label) -- Flow label
   h.payload_length = htons(payload_length)
   h.next_header = next_header
   h.hop_limit = constants.default_ttl
   h.src_ip = src
   h.dst_ip = dst
end

local function calculate_icmp_payload_size(dst_pkt, initial_pkt, max_size, config)
   local original_bytes_to_skip = ethernet_header_size
   if config.extra_payload_offset then
      original_bytes_to_skip = original_bytes_to_skip + config.extra_payload_offset
   end
   local payload_size = initial_pkt.length - original_bytes_to_skip
   local non_payload_bytes = dst_pkt.length + constants.icmp_base_size
   local full_pkt_size = payload_size + non_payload_bytes
   if full_pkt_size > max_size + ethernet_header_size then
      full_pkt_size = max_size + ethernet_header_size
      payload_size = full_pkt_size - non_payload_bytes
   end
   return payload_size, original_bytes_to_skip, non_payload_bytes
end

-- Write ICMP data to the end of a packet
-- Config must contain code and type
-- Config may contain a 'next_hop_mtu' setting.

local function write_icmp(dst_pkt, initial_pkt, max_size, base_checksum, config)
   local payload_size, original_bytes_to_skip, non_payload_bytes =
      calculate_icmp_payload_size(dst_pkt, initial_pkt, max_size, config)
   local off = dst_pkt.length
   dst_pkt.data[off] = config.type
   dst_pkt.data[off + 1] = config.code
   wr16(dst_pkt.data + off + 2, 0) -- checksum
   wr32(dst_pkt.data + off + 4, 0) -- Reserved
   if config.next_hop_mtu then
      wr16(dst_pkt.data + off + 6, htons(config.next_hop_mtu))
   end
   local dest = dst_pkt.data + non_payload_bytes
   ffi.C.memmove(dest, initial_pkt.data + original_bytes_to_skip, payload_size)

   local icmp_bytes = constants.icmp_base_size + payload_size
   local icmp_start = dst_pkt.data + dst_pkt.length
   local csum = checksum.ipsum(icmp_start, icmp_bytes, base_checksum)
   wr16(dst_pkt.data + off + 2, htons(csum))

   dst_pkt.length = dst_pkt.length + icmp_bytes
end

local function to_datagram(pkt)
   return datagram:new(pkt)
end

-- initial_pkt is the one to embed (a subset of) in the ICMP payload
function new_icmpv4_packet(from_ip, to_ip, initial_pkt, config)
   local new_pkt = packet.allocate()
   local dgram = to_datagram(new_pkt)
   local ipv4_header = ipv4:new({ttl = constants.default_ttl,
                                 protocol = constants.proto_icmp,
                                 src = from_ip, dst = to_ip})
   dgram:push(ipv4_header)
   new_pkt = dgram:packet()
   ipv4_header:free()
   new_pkt = prepend_ethernet_header(new_pkt, n_ethertype_ipv4)

   -- Generate RFC 1812 ICMPv4 packets, which carry as much payload as they can,
   -- rather than RFC 792 packets, which only carry the original IPv4 header + 8 octets
   write_icmp(new_pkt, initial_pkt, constants.max_icmpv4_packet_size, 0, config)

   -- Fix up the IPv4 total length and checksum
   local new_ipv4_len = new_pkt.length - ethernet_header_size
   local ip_tl_p = new_pkt.data + ethernet_header_size + constants.o_ipv4_total_length
   wr16(ip_tl_p, ntohs(new_ipv4_len))
   local ip_checksum_p = new_pkt.data + ethernet_header_size + constants.o_ipv4_checksum
   wr16(ip_checksum_p,  0) -- zero out the checksum before recomputing
   local csum = checksum.ipsum(new_pkt.data + ethernet_header_size, new_ipv4_len, 0)
   wr16(ip_checksum_p, htons(csum))

   return new_pkt
end

function new_icmpv6_packet(from_ip, to_ip, initial_pkt, config)
   local new_pkt = packet.allocate()
   local dgram = to_datagram(new_pkt)
   local ipv6_header = ipv6:new({hop_limit = constants.default_ttl,
                                 next_header = constants.proto_icmpv6,
                                 src = from_ip, dst = to_ip})
   dgram:push(ipv6_header)
   new_pkt = prepend_ethernet_header(dgram:packet(), n_ethertype_ipv6)

   local max_size = constants.max_icmpv6_packet_size
   local ph_len = calculate_icmp_payload_size(new_pkt, initial_pkt, max_size, config) + constants.icmp_base_size
   local ph = ipv6_header:pseudo_header(ph_len, constants.proto_icmpv6)
   local ph_csum = checksum.ipsum(ffi.cast("uint8_t*", ph), ffi.sizeof(ph), 0)
   ph_csum = band(bnot(ph_csum), 0xffff)
   write_icmp(new_pkt, initial_pkt, max_size, ph_csum, config)

   local new_ipv6_len = new_pkt.length - (constants.ipv6_fixed_header_size + ethernet_header_size)
   local ip_pl_p = new_pkt.data + ethernet_header_size + constants.o_ipv6_payload_len
   wr16(ip_pl_p, ntohs(new_ipv6_len))

   ipv6_header:free()
   return new_pkt
end

-- This function converts between IPv4-as-host-uint32 and IPv4 as
-- uint8_t[4].  It's a stopgap measure; really the rest of the code
-- should be converted to use IPv4-as-host-uint32.
local function convert_ipv4(addr)
   local str = require('lib.yang.util').ipv4_ntop(addr)
   return require('lib.protocol.ipv4'):pton(str)
end

local function drop(pkt)
   packet.free(pkt)
end

LwAftr = { yang_schema = 'snabb-softwire-v3' }
-- Fields:
--   - direction: "in", "out", "hairpin", "drop";
--   If "direction" is "drop":
--     - reason: reasons for dropping;
--   - protocol+version: "icmpv4", "icmpv6", "ipv4", "ipv6";
--   - size: "bytes", "packets".
LwAftr.shm = {
   ["drop-all-ipv4-iface-bytes"]                       = {counter},
   ["drop-all-ipv4-iface-packets"]                     = {counter},
   ["drop-all-ipv6-iface-bytes"]                       = {counter},
   ["drop-all-ipv6-iface-packets"]                     = {counter},
   ["drop-bad-checksum-icmpv4-bytes"]                  = {counter},
   ["drop-bad-checksum-icmpv4-packets"]                = {counter},
   ["drop-in-by-policy-icmpv4-bytes"]                  = {counter},
   ["drop-in-by-policy-icmpv4-packets"]                = {counter},
   ["drop-in-by-policy-icmpv6-bytes"]                  = {counter},
   ["drop-in-by-policy-icmpv6-packets"]                = {counter},
   ["drop-in-by-rfc7596-icmpv4-bytes"]                 = {counter},
   ["drop-in-by-rfc7596-icmpv4-packets"]               = {counter},
   ["drop-ipv4-frag-disabled"]                         = {counter},
   ["drop-ipv6-frag-disabled"]                         = {counter},
   ["drop-misplaced-not-ipv4-bytes"]                   = {counter},
   ["drop-misplaced-not-ipv4-packets"]                 = {counter},
   ["drop-misplaced-not-ipv6-bytes"]                   = {counter},
   ["drop-misplaced-not-ipv6-packets"]                 = {counter},
   ["drop-no-dest-softwire-ipv4-bytes"]                = {counter},
   ["drop-no-dest-softwire-ipv4-packets"]              = {counter},
   ["drop-no-source-softwire-ipv6-bytes"]              = {counter},
   ["drop-no-source-softwire-ipv6-packets"]            = {counter},
   ["drop-out-by-policy-icmpv4-packets"]               = {counter},
   ["drop-out-by-policy-icmpv6-packets"]               = {counter},
   ["drop-over-mtu-but-dont-fragment-ipv4-bytes"]      = {counter},
   ["drop-over-mtu-but-dont-fragment-ipv4-packets"]    = {counter},
   ["drop-over-rate-limit-icmpv6-bytes"]               = {counter},
   ["drop-over-rate-limit-icmpv6-packets"]             = {counter},
   ["drop-over-time-but-not-hop-limit-icmpv6-bytes"]   = {counter},
   ["drop-over-time-but-not-hop-limit-icmpv6-packets"] = {counter},
   ["drop-too-big-type-but-not-code-icmpv6-bytes"]     = {counter},
   ["drop-too-big-type-but-not-code-icmpv6-packets"]   = {counter},
   ["drop-ttl-zero-ipv4-bytes"]                        = {counter},
   ["drop-ttl-zero-ipv4-packets"]                      = {counter},
   ["drop-unknown-protocol-icmpv6-bytes"]              = {counter},
   ["drop-unknown-protocol-icmpv6-packets"]            = {counter},
   ["drop-unknown-protocol-ipv6-bytes"]                = {counter},
   ["drop-unknown-protocol-ipv6-packets"]              = {counter},
   ["hairpin-ipv4-bytes"]                              = {counter},
   ["hairpin-ipv4-packets"]                            = {counter},
   ["ingress-packet-drops"]                            = {counter},
   ["in-ipv4-bytes"]                                   = {counter},
   ["in-ipv4-packets"]                                 = {counter},
   ["in-ipv6-bytes"]                                   = {counter},
   ["in-ipv6-packets"]                                 = {counter},
   ["out-icmpv4-error-bytes"]                          = {counter},
   ["out-icmpv4-error-packets"]                        = {counter},
   ["out-icmpv6-error-bytes"]                          = {counter},
   ["out-icmpv6-error-packets"]                        = {counter},
   ["out-ipv4-bytes"]                                  = {counter},
   ["out-ipv4-packets"]                                = {counter},
   ["out-ipv6-bytes"]                                  = {counter},
   ["out-ipv6-packets"]                                = {counter},
}

function LwAftr:new(conf)
   if conf.debug then debug = true end
   local o = setmetatable({}, {__index=LwAftr})
   conf = lwutil.merge_instance(conf).softwire_config
   o.conf = conf
   o.binding_table = bt.load(conf.binding_table)
   o.inet_lookup_queue = bt.BTLookupQueue.new(o.binding_table)
   o.hairpin_lookup_queue = bt.BTLookupQueue.new(o.binding_table)

   o.icmpv4_error_count = 0
   o.icmpv4_error_rate_limit_start = 0
   o.icmpv6_error_count = 0
   o.icmpv6_error_rate_limit_start = 0

   alarms.add_to_inventory(
      {alarm_type_id='bad-ipv4-softwires-matches'},
      {resource=tostring(S.getpid()), has_clear=true,
       description="lwAFTR's bad matching softwires due to not found destination "..
          "address for IPv4 packets"})
   alarms.add_to_inventory(
      {alarm_type_id='bad-ipv6-softwires-matches'},
      {resource=tostring(S.getpid()), has_clear=true,
       description="lwAFTR's bad matching softwires due to not found source"..
          "address for IPv6 packets"})
   local bad_ipv4_softwire_matches = alarms.declare_alarm(
      {resource=tostring(S.getpid()), alarm_type_id='bad-ipv4-softwires-matches'},
      {perceived_severity = 'major',
       alarm_text = "lwAFTR's bad softwires matches due to non matching destination"..
         "address for incoming packets (IPv4) has reached over 100,000 softwires "..
         "binding-table.  Please review your lwAFTR's configuration binding-table."})
   local bad_ipv6_softwire_matches = alarms.declare_alarm(
      {resource=tostring(S.getpid()), alarm_type_id='bad-ipv6-softwires-matches'},
      {perceived_severity = 'major',
       alarm_text = "lwAFTR's bad softwires matches due to non matching source "..
         "address for outgoing packets (IPv6) has reached over 100,000 softwires "..
         "binding-table.  Please review your lwAFTR's configuration binding-table."})
   o.bad_ipv4_softwire_matches_alarm = CounterAlarm.new(bad_ipv4_softwire_matches,
      5, 1e5, o, 'drop-no-dest-softwire-ipv4-packets')
   o.bad_ipv6_softwire_matches_alarm = CounterAlarm.new(bad_ipv6_softwire_matches,
      5, 1e5, o, 'drop-no-source-softwire-ipv6-packets')

   if debug then lwdebug.pp(conf) end
   return o
end

-- The following two methods are called by lib.ptree.worker in reaction
-- to binding table changes, via
-- lib/ptree/support/snabb-softwire-v3.lua.
function LwAftr:add_softwire_entry(entry_blob)
   self.binding_table:add_softwire_entry(entry_blob)
end
function LwAftr:remove_softwire_entry(entry_key_blob)
   self.binding_table:remove_softwire_entry(entry_key_blob)
end

local function decrement_ttl(pkt)
   local ipv4_header = get_ethernet_payload(pkt)
   local chksum = bnot(ntohs(rd16(ipv4_header + o_ipv4_checksum)))
   local old_ttl = ipv4_header[o_ipv4_ttl]
   if old_ttl == 0 then return 0 end
   local new_ttl = band(old_ttl - 1, 0xff)
   ipv4_header[o_ipv4_ttl] = new_ttl
   -- Now fix up the checksum.  o_ipv4_ttl is the first byte in the
   -- 16-bit big-endian word, so the difference to the overall sum is
   -- multiplied by 0xff.
   chksum = chksum + lshift(new_ttl - old_ttl, 8)
   -- Now do the one's complement 16-bit addition of the 16-bit words of
   -- the checksum, which necessarily is a 32-bit value.  Two carry
   -- iterations will suffice.
   chksum = band(chksum, 0xffff) + rshift(chksum, 16)
   chksum = band(chksum, 0xffff) + rshift(chksum, 16)
   wr16(ipv4_header + o_ipv4_checksum, htons(bnot(chksum)))
   return new_ttl
end

function LwAftr:ipv4_in_binding_table (ip)
   return self.binding_table:is_managed_ipv4_address(ip)
end

function LwAftr:transmit_icmpv6_reply (pkt)
   local now = tonumber(engine.now())
   -- Reset if elapsed time reached.
   local rate_limiting = self.conf.internal_interface.error_rate_limiting
   if now - self.icmpv6_error_rate_limit_start >= rate_limiting.period then
      self.icmpv6_error_rate_limit_start = now
      self.icmpv6_error_count = 0
   end
   -- Send packet if limit not reached.
   if self.icmpv6_error_count < rate_limiting.packets then
      self.icmpv6_error_count = self.icmpv6_error_count + 1
      counter.add(self.shm["out-icmpv6-error-bytes"], pkt.length)
      counter.add(self.shm["out-icmpv6-error-packets"])
      counter.add(self.shm["out-ipv6-bytes"], pkt.length)
      counter.add(self.shm["out-ipv6-packets"])
      return transmit(self.o6, pkt)
   else
      counter.add(self.shm["drop-over-rate-limit-icmpv6-bytes"], pkt.length)
      counter.add(self.shm["drop-over-rate-limit-icmpv6-packets"])
      return drop(pkt)
   end
end

function LwAftr:drop_ipv4(pkt, pkt_src_link)
   if pkt_src_link == PKT_FROM_INET then
      counter.add(self.shm["drop-all-ipv4-iface-bytes"], pkt.length)
      counter.add(self.shm["drop-all-ipv4-iface-packets"])
   elseif pkt_src_link == PKT_HAIRPINNED then
      -- B4s emit packets with no IPv6 extension headers.
      local orig_packet_len = pkt.length + ipv6_fixed_header_size
      counter.add(self.shm["drop-all-ipv6-iface-bytes"], orig_packet_len)
      counter.add(self.shm["drop-all-ipv6-iface-packets"])
   else
      assert(false, "Programming error, bad pkt_src_link: " .. pkt_src_link)
   end
   return drop(pkt)
end

function LwAftr:transmit_icmpv4_reply(pkt, orig_pkt, orig_pkt_link)
   local now = tonumber(engine.now())
   -- Reset if elapsed time reached.
   local rate_limiting = self.conf.external_interface.error_rate_limiting
   if now - self.icmpv4_error_rate_limit_start >= rate_limiting.period then
      self.icmpv4_error_rate_limit_start = now
      self.icmpv4_error_count = 0
   end
   -- Origin packet is always dropped.
   if orig_pkt_link then
      self:drop_ipv4(orig_pkt, orig_pkt_link)
   else
      drop(orig_pkt)
   end
   -- Send packet if limit not reached.
   if self.icmpv4_error_count < rate_limiting.packets then
      self.icmpv4_error_count = self.icmpv4_error_count + 1
      counter.add(self.shm["out-icmpv4-error-bytes"], pkt.length)
      counter.add(self.shm["out-icmpv4-error-packets"])
      -- Only locally generated error packets are handled here.  We transmit
      -- them right away, instead of calling transmit_ipv4, because they are
      -- never hairpinned and should not be counted by the "out-ipv4" counter.
      -- However, they should be tunneled if the error is to be sent to a host
      -- behind a B4, whether or not hairpinning is enabled; this is not hairpinning.
      -- ... and the tunneling should happen via the 'hairpinning' queue, to make
      -- sure counters are handled appropriately, despite this not being hairpinning.
      -- This avoids having phantom incoming IPv4 packets.
      local ipv4_header = get_ethernet_payload(pkt)
      local dst_ip = get_ipv4_dst_address(ipv4_header)
      if self:ipv4_in_binding_table(dst_ip) then
         return transmit(self.input.hairpin_in, pkt)
      else
         counter.add(self.shm["out-ipv4-bytes"], pkt.length)
         counter.add(self.shm["out-ipv4-packets"])
         return transmit(self.o4, pkt)
      end
   else
      return drop(pkt)
   end
end

-- Hairpinned packets need to be handled quite carefully. We've decided they:
-- * should increment hairpin-ipv4-bytes and hairpin-ipv4-packets
-- * should increment [in|out]-ipv6-[bytes|packets]
-- * should NOT increment  [in|out]-ipv4-[bytes|packets]
-- The latter is because decapsulating and re-encapsulating them via IPv4
-- packets is an internal implementation detail that DOES NOT go out over
-- physical wires.
-- Not incrementing out-ipv4-bytes and out-ipv4-packets is straightforward.
-- Not incrementing in-ipv4-[bytes|packets] is harder. The easy way would be
-- to add extra flags and conditionals, but it's expected that a high enough
-- percentage of traffic might be hairpinned that this could be problematic,
-- (and a nightmare as soon as we add any kind of parallelism)
-- so instead we speculatively decrement the counters here.
-- It is assumed that any packet we transmit to self.input.v4 will not
-- be dropped before the in-ipv4-[bytes|packets] counters are incremented;
-- I *think* this approach bypasses using the physical NIC but am not
-- absolutely certain.
function LwAftr:transmit_ipv4(pkt)
   local ipv4_header = get_ethernet_payload(pkt)
   local dst_ip = get_ipv4_dst_address(ipv4_header)
   if (self.conf.internal_interface.hairpinning and
       self:ipv4_in_binding_table(dst_ip)) then
      -- The destination address is managed by the lwAFTR, so we need to
      -- hairpin this packet.  Enqueue on the IPv4 interface, as if it
      -- came from the internet.
      counter.add(self.shm["hairpin-ipv4-bytes"], pkt.length)
      counter.add(self.shm["hairpin-ipv4-packets"])
      return transmit(self.input.hairpin_in, pkt)
   else
      counter.add(self.shm["out-ipv4-bytes"], pkt.length)
      counter.add(self.shm["out-ipv4-packets"])
      return transmit(self.o4, pkt)
   end
end

-- ICMPv4 type 3 code 1, as per RFC 7596.
-- The target IPv4 address + port is not in the table.
function LwAftr:drop_ipv4_packet_to_unreachable_host(pkt, pkt_src_link)
   counter.add(self.shm["drop-no-dest-softwire-ipv4-bytes"], pkt.length)
   counter.add(self.shm["drop-no-dest-softwire-ipv4-packets"])

   if not self.conf.external_interface.generate_icmp_errors then
      -- ICMP error messages off by policy; silently drop.
      -- Not counting bytes because we do not even generate the packets.
      counter.add(self.shm["drop-out-by-policy-icmpv4-packets"])
      return self:drop_ipv4(pkt, pkt_src_link)
   end

   if get_ipv4_proto(get_ethernet_payload(pkt)) == proto_icmp then
      -- RFC 7596 section 8.1 requires us to silently drop incoming
      -- ICMPv4 messages that don't match the binding table.
      counter.add(self.shm["drop-in-by-rfc7596-icmpv4-bytes"], pkt.length)
      counter.add(self.shm["drop-in-by-rfc7596-icmpv4-packets"])
      return self:drop_ipv4(pkt, pkt_src_link)
   end

   local ipv4_header = get_ethernet_payload(pkt)
   local to_ip = get_ipv4_src_address_ptr(ipv4_header)
   local icmp_config = {
      type = constants.icmpv4_dst_unreachable,
      code = constants.icmpv4_host_unreachable,
   }
   local icmp_dis = new_icmpv4_packet(
      convert_ipv4(self.conf.external_interface.ip),
      to_ip, pkt, icmp_config)

   return self:transmit_icmpv4_reply(icmp_dis, pkt, pkt_src_link)
end

-- ICMPv6 type 1 code 5, as per RFC 7596.
-- The source (ipv6, ipv4, port) tuple is not in the table.
function LwAftr:drop_ipv6_packet_from_bad_softwire(pkt, br_addr)
   if not self.conf.internal_interface.generate_icmp_errors then
      -- ICMP error messages off by policy; silently drop.
      -- Not counting bytes because we do not even generate the packets.
      counter.add(self.shm["drop-out-by-policy-icmpv6-packets"])
      return drop(pkt)
   end

   local ipv6_header = get_ethernet_payload(pkt)
   local orig_src_addr_icmp_dst = get_ipv6_src_address(ipv6_header)
   -- If br_addr is specified, use that as the source addr. Otherwise, send it
   -- back from the IPv6 address it was sent to.
   local icmpv6_src_addr = br_addr or get_ipv6_dst_address(ipv6_header)
   local icmp_config = {type = constants.icmpv6_dst_unreachable,
                        code = constants.icmpv6_failed_ingress_egress_policy,
                       }
   local b4fail_icmp = new_icmpv6_packet(
      icmpv6_src_addr, orig_src_addr_icmp_dst, pkt, icmp_config)
   drop(pkt)
   self:transmit_icmpv6_reply(b4fail_icmp)
end

function LwAftr:encapsulating_packet_with_df_flag_would_exceed_mtu(pkt)
   local payload_length = get_ethernet_payload_length(pkt)
   local mtu = self.conf.internal_interface.mtu
   if payload_length + ipv6_fixed_header_size <= mtu then
      -- Packet will not exceed MTU.
      return false
   end
   -- The result would exceed the IPv6 MTU; signal an error via ICMPv4 if
   -- the IPv4 fragment has the DF flag.
   return band(get_ipv4_flags(get_ethernet_payload(pkt)), 0x40) == 0x40
end

function LwAftr:cannot_fragment_df_packet_error(pkt)
   -- According to RFC 791, the original packet must be discarded.
   -- Return a packet with ICMP(3, 4) and the appropriate MTU
   -- as per https://tools.ietf.org/html/rfc2473#section-7.2
   if debug then lwdebug.print_pkt(pkt) end
   -- The ICMP packet should be set back to the packet's source.
   local dst_ip = get_ipv4_src_address_ptr(get_ethernet_payload(pkt))
   local mtu = self.conf.internal_interface.mtu
   local icmp_config = {
      type = constants.icmpv4_dst_unreachable,
      code = constants.icmpv4_datagram_too_big_df,
      extra_payload_offset = 0,
      next_hop_mtu = mtu - constants.ipv6_fixed_header_size,
   }
   return new_icmpv4_packet(
      convert_ipv4(self.conf.external_interface.ip),
      dst_ip, pkt, icmp_config)
end

function LwAftr:encapsulate_and_transmit(pkt, ipv6_dst, ipv6_src, pkt_src_link)
   -- Do not encapsulate packets that now have a ttl of zero or wrapped around
   local ttl = decrement_ttl(pkt)
   if ttl == 0 then
      counter.add(self.shm["drop-ttl-zero-ipv4-bytes"], pkt.length)
      counter.add(self.shm["drop-ttl-zero-ipv4-packets"])
      if not self.conf.external_interface.generate_icmp_errors then
         -- Not counting bytes because we do not even generate the packets.
         counter.add(self.shm["drop-out-by-policy-icmpv4-packets"])
         return self:drop_ipv4(pkt, pkt_src_link)
      end
      local ipv4_header = get_ethernet_payload(pkt)
      local dst_ip = get_ipv4_src_address_ptr(ipv4_header)
      local icmp_config = {type = constants.icmpv4_time_exceeded,
                           code = constants.icmpv4_ttl_exceeded_in_transit,
                           }
      local reply = new_icmpv4_packet(
         convert_ipv4(self.conf.external_interface.ip),
         dst_ip, pkt, icmp_config)

      return self:transmit_icmpv4_reply(reply, pkt, pkt_src_link)
   end

   if debug then print("ipv6", ipv6_src, ipv6_dst) end

   if self:encapsulating_packet_with_df_flag_would_exceed_mtu(pkt) then
      counter.add(self.shm["drop-over-mtu-but-dont-fragment-ipv4-bytes"], pkt.length)
      counter.add(self.shm["drop-over-mtu-but-dont-fragment-ipv4-packets"])
      if not self.conf.external_interface.generate_icmp_errors then
         -- Not counting bytes because we do not even generate the packets.
         counter.add(self.shm["drop-out-by-policy-icmpv4-packets"])
         return self:drop_ipv4(pkt, pkt_src_link)
      end
      local reply = self:cannot_fragment_df_packet_error(pkt)
      return self:transmit_icmpv4_reply(reply, pkt, pkt_src_link)
   end

   local payload_length = get_ethernet_payload_length(pkt)
   local l3_header = get_ethernet_payload(pkt)
   local traffic_class = get_ipv4_dscp_and_ecn(l3_header)
   local flow_label = self.conf.internal_interface.flow_label
   -- Note that this may invalidate any pointer into pkt.data.  Be warned!
   pkt = packet.shiftright(pkt, ipv6_header_size)
   write_ethernet_header(pkt, n_ethertype_ipv6)
   -- Fetch possibly-moved L3 header location.
   l3_header = get_ethernet_payload(pkt)

   write_ipv6_header(l3_header, ipv6_src, ipv6_dst, traffic_class,
                     flow_label, proto_ipv4, payload_length)

   if debug then
      print("encapsulated packet:")
      lwdebug.print_pkt(pkt)
   end

   counter.add(self.shm["out-ipv6-bytes"], pkt.length)
   counter.add(self.shm["out-ipv6-packets"])
   return transmit(self.o6, pkt)
end

function LwAftr:flush_encapsulation()
   local lq = self.inet_lookup_queue
   lq:process_queue()
   for n = 0, lq.length - 1 do
      local pkt, ipv6_dst, ipv6_src = lq:get_lookup(n)
      if ipv6_dst then
         self:encapsulate_and_transmit(pkt, ipv6_dst, ipv6_src, PKT_FROM_INET)
      else
         -- Lookup failed.
         if debug then print("lookup failed") end
         self:drop_ipv4_packet_to_unreachable_host(pkt, PKT_FROM_INET)
      end
   end
   lq:reset_queue()
end

function LwAftr:flush_hairpin()
   local lq = self.hairpin_lookup_queue
   lq:process_queue()
   for n = 0, lq.length - 1 do
      local pkt, ipv6_dst, ipv6_src = lq:get_lookup(n)
      if ipv6_dst then
         self:encapsulate_and_transmit(pkt, ipv6_dst, ipv6_src, PKT_HAIRPINNED)
      else
         -- Lookup failed. This can happen even with hairpinned packets, if
         -- the binding table changes between destination lookups.
         -- Count the original IPv6 packet as dropped, not the hairpinned one.
         if debug then print("lookup failed") end
         self:drop_ipv4_packet_to_unreachable_host(pkt, PKT_HAIRPINNED)
      end
   end
   lq:reset_queue()
end

function LwAftr:enqueue_encapsulation(pkt, ipv4, port, pkt_src_link)
   if pkt_src_link == PKT_FROM_INET then
      self.inet_lookup_queue:enqueue_lookup(pkt, ipv4, port)
   else
      assert(pkt_src_link == PKT_HAIRPINNED)
      self.hairpin_lookup_queue:enqueue_lookup(pkt, ipv4, port)
   end
end

function LwAftr:icmpv4_incoming(pkt, pkt_src_link)
   local ipv4_header = get_ethernet_payload(pkt)
   local ipv4_header_size = get_ipv4_header_length(ipv4_header)
   local icmp_header = get_ipv4_payload(ipv4_header)
   local icmp_type = get_icmp_type(icmp_header)

   -- RFC 7596 is silent on whether to validate echo request/reply checksums.
   -- ICMP checksums SHOULD be validated according to RFC 5508.
   -- Choose to verify the echo reply/request ones too.
   -- Note: the lwaftr SHOULD NOT validate the transport checksum of the embedded packet.
   -- Were it to nonetheless do so, RFC 4884 extension headers MUST NOT
   -- be taken into account when validating the checksum
   local icmp_bytes = get_ipv4_total_length(ipv4_header) - ipv4_header_size
   if checksum.ipsum(icmp_header, icmp_bytes, 0) ~= 0 then
      -- Silently drop the packet, as per RFC 5508
      counter.add(self.shm["drop-bad-checksum-icmpv4-bytes"], pkt.length)
      counter.add(self.shm["drop-bad-checksum-icmpv4-packets"])
      return self:drop_ipv4(pkt, pkt_src_link)
   end

   local ipv4_dst = get_ipv4_dst_address(ipv4_header)
   local port

   -- checksum was ok
   if icmp_type == constants.icmpv4_echo_request then
      -- For an incoming ping from the IPv4 internet, assume port == 0
      -- for the purposes of looking up a softwire in the binding table.
      -- This will allow ping to a B4 on an IPv4 without port sharing.
      -- It also has the nice property of causing a drop if the IPv4 has
      -- any reserved ports.
      --
      -- RFC 7596 section 8.1 seems to suggest that we should use the
      -- echo identifier for this purpose, but that only makes sense for
      -- echo requests originating from a B4, to identify the softwire
      -- of the source.  It can't identify a destination softwire.  This
      -- makes sense because you can't really "ping" a port-restricted
      -- IPv4 address.
      port = 0
   elseif icmp_type == constants.icmpv4_echo_reply then
      -- A reply to a ping that originally issued from a subscriber on
      -- the B4 side; the B4 set the port in the echo identifier, as per
      -- RFC 7596, section 8.1, so use that to look up the destination
      -- softwire.
      port = get_icmpv4_echo_identifier(icmp_header)
   else
      -- As per REQ-3, use the ip address embedded in the ICMP payload,
      -- assuming that the payload is shaped like TCP or UDP with the
      -- ports first.
      local embedded_ipv4_header = get_icmp_payload(icmp_header)
      port = get_ipv4_payload_src_port(embedded_ipv4_header)
   end

   return self:enqueue_encapsulation(pkt, ipv4_dst, port, pkt_src_link)
end

-- The incoming packet is a complete one with ethernet headers.
-- FIXME: Verify that the total_length declared in the packet is correct.
function LwAftr:from_inet(pkt, pkt_src_link)
   -- Check incoming ICMP -first-, because it has different binding table lookup logic
   -- than other protocols.
   local ipv4_header = get_ethernet_payload(pkt)
   if get_ipv4_proto(ipv4_header) == proto_icmp then
      if not self.conf.external_interface.allow_incoming_icmp then
         counter.add(self.shm["drop-in-by-policy-icmpv4-bytes"], pkt.length)
         counter.add(self.shm["drop-in-by-policy-icmpv4-packets"])
         return self:drop_ipv4(pkt, pkt_src_link)
      else
         return self:icmpv4_incoming(pkt, pkt_src_link)
      end
   end

   -- If fragmentation support is enabled, the lwAFTR never receives fragments.
   -- If it does, fragment support is disabled and it should drop them.
   if is_ipv4_fragment(pkt) then
      counter.add(self.shm["drop-ipv4-frag-disabled"])
      return self:drop_ipv4(pkt, pkt_src_link)
   end
   -- It's not incoming ICMP.  Assume we can find ports in the IPv4
   -- payload, as in TCP and UDP.  We could check strictly for TCP/UDP,
   -- but that would filter out similarly-shaped protocols like SCTP, so
   -- we optimistically assume that the incoming traffic has the right
   -- shape.
   local dst_ip = get_ipv4_dst_address(ipv4_header)
   local dst_port = get_ipv4_payload_dst_port(ipv4_header)

   return self:enqueue_encapsulation(pkt, dst_ip, dst_port, pkt_src_link)
end

function LwAftr:tunnel_unreachable(pkt, code, next_hop_mtu)
   local ipv6_header = get_ethernet_payload(pkt)
   local icmp_header = get_ipv6_payload(ipv6_header)
   local embedded_ipv6_header = get_icmp_payload(icmp_header)
   local embedded_ipv4_header = get_ipv6_payload(embedded_ipv6_header)

   local icmp_config = {type = constants.icmpv4_dst_unreachable,
                        code = code,
                        extra_payload_offset = embedded_ipv4_header - ipv6_header,
                        next_hop_mtu = next_hop_mtu
                        }
   local dst_ip = get_ipv4_src_address_ptr(embedded_ipv4_header)
   local icmp_reply = new_icmpv4_packet(
      convert_ipv4(self.conf.external_interface.ip),
      dst_ip, pkt, icmp_config)
   return icmp_reply
end

-- FIXME: Verify that the softwire is in the the binding table.
function LwAftr:icmpv6_incoming(pkt)
   local ipv6_header = get_ethernet_payload(pkt)
   local icmp_header = get_ipv6_payload(ipv6_header)
   local icmp_type = get_icmp_type(icmp_header)
   local icmp_code = get_icmp_code(icmp_header)
   if icmp_type == constants.icmpv6_packet_too_big then
      if icmp_code ~= constants.icmpv6_code_packet_too_big then
         -- Invalid code.
         counter.add(self.shm["drop-too-big-type-but-not-code-icmpv6-bytes"],
            pkt.length)
         counter.add(self.shm["drop-too-big-type-but-not-code-icmpv6-packets"])
         counter.add(self.shm["drop-all-ipv6-iface-bytes"], pkt.length)
         counter.add(self.shm["drop-all-ipv6-iface-packets"])
         return drop(pkt)
      end
      local mtu = get_icmp_mtu(icmp_header) - constants.ipv6_fixed_header_size
      local reply = self:tunnel_unreachable(pkt,
                                            constants.icmpv4_datagram_too_big_df,
                                            mtu)
      return self:transmit_icmpv4_reply(reply, pkt)
   -- Take advantage of having already checked for 'packet too big' (2), and
   -- unreachable node/hop limit exceeded/paramater problem being 1, 3, 4 respectively
   elseif icmp_type <= constants.icmpv6_parameter_problem then
      -- If the time limit was exceeded, require it was a hop limit code
      if icmp_type == constants.icmpv6_time_limit_exceeded then
         if icmp_code ~= constants.icmpv6_hop_limit_exceeded then
            counter.add(self.shm[
               "drop-over-time-but-not-hop-limit-icmpv6-bytes"], pkt.length)
            counter.add(
               self.shm["drop-over-time-but-not-hop-limit-icmpv6-packets"])
            counter.add(self.shm["drop-all-ipv6-iface-bytes"], pkt.length)
            counter.add(self.shm["drop-all-ipv6-iface-packets"])
            return drop(pkt)
         end
      end
      -- Accept all unreachable or parameter problem codes
      local reply = self:tunnel_unreachable(pkt,
                                            constants.icmpv4_host_unreachable)
      return self:transmit_icmpv4_reply(reply, pkt)
   else
      -- No other types of ICMPv6, including echo request/reply, are
      -- handled.
      counter.add(self.shm["drop-unknown-protocol-icmpv6-bytes"], pkt.length)
      counter.add(self.shm["drop-unknown-protocol-icmpv6-packets"])
      counter.add(self.shm["drop-all-ipv6-iface-bytes"], pkt.length)
      counter.add(self.shm["drop-all-ipv6-iface-packets"])
      return drop(pkt)
   end
end

function LwAftr:flush_decapsulation()
   local lq = self.inet_lookup_queue
   lq:process_queue()
   for n = 0, lq.length - 1 do
      local pkt, b4_addr, br_addr = lq:get_lookup(n)

      local ipv6_header = get_ethernet_payload(pkt)
      if (b4_addr
          and ipv6_equals(get_ipv6_src_address(ipv6_header), b4_addr)
          and ipv6_equals(get_ipv6_dst_address(ipv6_header), br_addr)) then
         -- Source softwire is valid; decapsulate and forward.
         -- Note that this may invalidate any pointer into pkt.data.  Be warned!
         pkt = packet.shiftleft(pkt, ipv6_fixed_header_size)
         write_ethernet_header(pkt, n_ethertype_ipv4)
         self:transmit_ipv4(pkt)
      else
         counter.add(self.shm["drop-no-source-softwire-ipv6-bytes"], pkt.length)
         counter.add(self.shm["drop-no-source-softwire-ipv6-packets"])
         counter.add(self.shm["drop-all-ipv6-iface-bytes"], pkt.length)
         counter.add(self.shm["drop-all-ipv6-iface-packets"])
         self:drop_ipv6_packet_from_bad_softwire(pkt, br_addr)
      end
   end
   lq:reset_queue()
end

function LwAftr:enqueue_decapsulation(pkt, ipv4, port)
   self.inet_lookup_queue:enqueue_lookup(pkt, ipv4, port)
end

-- FIXME: Verify that the packet length is big enough?
function LwAftr:from_b4(pkt)
   -- If fragmentation support is enabled, the lwAFTR never receives fragments.
   -- If it does, fragment support is disabled and it should drop them.
   if is_ipv6_fragment(pkt) then
      counter.add(self.shm["drop-ipv6-frag-disabled"])
      counter.add(self.shm["drop-all-ipv6-iface-bytes"], pkt.length)
      counter.add(self.shm["drop-all-ipv6-iface-packets"])
      return drop(pkt)
   end
   local ipv6_header = get_ethernet_payload(pkt)
   local proto = get_ipv6_next_header(ipv6_header)

   if proto ~= proto_ipv4 then
      if proto == proto_icmpv6 then
         if not self.conf.internal_interface.allow_incoming_icmp then
            counter.add(self.shm["drop-in-by-policy-icmpv6-bytes"], pkt.length)
            counter.add(self.shm["drop-in-by-policy-icmpv6-packets"])
            counter.add(self.shm["drop-all-ipv6-iface-bytes"], pkt.length)
            counter.add(self.shm["drop-all-ipv6-iface-packets"])
            return drop(pkt)
         else
            return self:icmpv6_incoming(pkt)
         end
      else
         -- Drop packet with unknown protocol.
         counter.add(self.shm["drop-unknown-protocol-ipv6-bytes"], pkt.length)
         counter.add(self.shm["drop-unknown-protocol-ipv6-packets"])
         counter.add(self.shm["drop-all-ipv6-iface-bytes"], pkt.length)
         counter.add(self.shm["drop-all-ipv6-iface-packets"])
         return drop(pkt)
      end
   end

   local tunneled_ipv4_header = get_ipv6_payload(ipv6_header)
   local port
   if get_ipv4_proto(tunneled_ipv4_header) == proto_icmp then
      local icmp_header = get_ipv4_payload(tunneled_ipv4_header)
      local icmp_type = get_icmp_type(icmp_header)
      if icmp_type == constants.icmpv4_echo_request then
         -- A ping going out from the B4 to the internet; the B4 will
         -- encode a port in its range into the echo identifier, as per
         -- RFC 7596 section 8.
         port = get_icmpv4_echo_identifier(icmp_header)
      elseif icmp_type == constants.icmpv4_echo_reply then
         -- A reply to a ping, coming from the B4.  Only B4s whose
         -- softwire is associated with port 0 are pingable.  See
         -- icmpv4_incoming for more discussion.
         port = 0
      else
         -- Otherwise it's an error in response to a non-ICMP packet,
         -- routed to the B4 via the ports in IPv4 payload.  Extract
         -- these ports from the embedded packet fragment in the ICMP
         -- payload.
         local embedded_ipv4_header = get_icmp_payload(icmp_header)
         port = get_ipv4_payload_src_port(embedded_ipv4_header)
      end
   else
      -- It's not ICMP.  Assume we can find ports in the IPv4 payload,
      -- as in TCP and UDP.  We could check strictly for TCP/UDP, but
      -- that would filter out similarly-shaped protocols like SCTP, so
      -- we optimistically assume that the incoming traffic has the
      -- right shape.
      port = get_ipv4_payload_src_port(tunneled_ipv4_header)
   end

   local ipv4 = get_ipv4_src_address(tunneled_ipv4_header)
   return self:enqueue_decapsulation(pkt, ipv4, port)
end

function LwAftr:push ()
   local i4, i6, ih = self.input.v4, self.input.v6, self.input.hairpin_in
   local o4, o6 = self.output.v4, self.output.v6
   self.o4, self.o6 = o4, o6

   self.bad_ipv4_softwire_matches_alarm:check()
   self.bad_ipv6_softwire_matches_alarm:check()

   for _ = 1, link.nreadable(i6) do
      -- Decapsulate incoming IPv6 packets from the B4 interface and
      -- push them out the V4 link, unless they need hairpinning, in
      -- which case enqueue them on the hairpinning incoming link.
      -- Drop anything that's not IPv6.
      local pkt = receive(i6)
      if is_ipv6(pkt) then
         counter.add(self.shm["in-ipv6-bytes"], pkt.length)
         counter.add(self.shm["in-ipv6-packets"])
         self:from_b4(pkt)
      else
         counter.add(self.shm["drop-misplaced-not-ipv6-bytes"], pkt.length)
         counter.add(self.shm["drop-misplaced-not-ipv6-packets"])
         counter.add(self.shm["drop-all-ipv6-iface-bytes"], pkt.length)
         counter.add(self.shm["drop-all-ipv6-iface-packets"])
         drop(pkt)
      end
   end
   self:flush_decapsulation()

   for _ = 1, link.nreadable(i4) do
      -- Encapsulate incoming IPv4 packets, excluding hairpinned
      -- packets.  Drop anything that's not IPv4.
      local pkt = receive(i4)
      if is_ipv4(pkt) then
         counter.add(self.shm["in-ipv4-bytes"], pkt.length)
         counter.add(self.shm["in-ipv4-packets"])
         self:from_inet(pkt, PKT_FROM_INET)
      else
         counter.add(self.shm["drop-misplaced-not-ipv4-bytes"], pkt.length)
         counter.add(self.shm["drop-misplaced-not-ipv4-packets"])
         -- It's guaranteed to not be hairpinned.
         counter.add(self.shm["drop-all-ipv4-iface-bytes"], pkt.length)
         counter.add(self.shm["drop-all-ipv4-iface-packets"])
         drop(pkt)
      end
   end
   self:flush_encapsulation()

   for _ = 1, link.nreadable(ih) do
      -- Encapsulate hairpinned packet.
      local pkt = receive(ih)
      -- To reach this link, it has to have come through the lwaftr, so it
      -- is certainly IPv4. It was already counted, no more counter updates.
      self:from_inet(pkt, PKT_HAIRPINNED)
   end
   self:flush_hairpin()
end
