module(..., package.seeall)

local constants = require("apps.lwaftr.constants")
local lwutil = require("apps.lwaftr.lwutil")
local packet = require("core.packet")
local ipsum = require("lib.checksum").ipsum
local bit = require("bit")
local ffi = require("ffi")

local rd16, wr16, get_ihl = lwutil.rd16, lwutil.wr16, lwutil.get_ihl
local cast = ffi.cast
local C = ffi.C
local band, bor = bit.band, bit.bor
local ceil = math.ceil

local ver_and_ihl_offset = constants.ethernet_header_size + constants.o_ipv4_ver_and_ihl
local total_length_offset = constants.ethernet_header_size + constants.o_ipv4_total_length
local frag_id_offset = constants.ethernet_header_size + constants.o_ipv4_identification
local flags_and_frag_offset_offset = constants.ethernet_header_size + constants.o_ipv4_flags
local checksum_offset = constants.ethernet_header_size + constants.o_ipv4_checksum

-- Constants to manipulate the flags next to the frag-offset field directly
-- as a 16-bit integer, without needing to shift the 3 flag bits.
local flag_dont_fragment_mask  = 0x4000
local flag_more_fragments_mask = 0x2000
local frag_offset_field_mask   = 0x1FFF


-- TODO: Consider security/performance tradeoffs of randomization
local fresh_frag_id = (function ()
   local internal_frag_id = 0x4242
   return function ()
      internal_frag_id = band(internal_frag_id + 1, 0xFFFF)
      return internal_frag_id
   end
end)()


FRAGMENT_OK = 1
FRAGMENT_UNNEEDED = 2
FRAGMENT_FORBIDDEN = 3

--
-- IPv4 fragmentation, as per https://tools.ietf.org/html/rfc791
--
-- For an invocation:
--
--    local statuscode, packets = fragment_ipv4(input_packet, mtu)
--
-- the possible values for the returned "statuscode" are:
--
--   * FRAGMENT_OK: the returned "packets" is a list of IPv4 packets, all
--     of them smaller or equal than "mtu" bytes, which contain the payload
--     from the "input_packet" properly fragmented. Note that "input_packet"
--     is modified in-place.
--
--   * FRAGMENT_UNNEEDED: the returned "packets" is the same object as
--     "input_packet", unmodified. This is the case when the size of packet
--     is smaller or equal than "mtu" bytes.
--
--   * FRAGMENT_FORBIDDEN: the returned "packets" will be "nil". This is
--     the case when "input_packet" has the "don't fragment" flag set, and
--     its size is bigger than "mtu" bytes. Client code may want to return
--     an ICMP Datagram Too Big (Type 3, Code 4) packet back to the sender.
--
function fragment_ipv4(ipv4_pkt, mtu)
   if ipv4_pkt.length <= mtu then
      return FRAGMENT_UNNEEDED, ipv4_pkt
   end

   -- Discard packets with the DF (dont't fragment) flag set
   do
      local flags_and_frag_offset = C.ntohs(rd16(ipv4_pkt.data + flags_and_frag_offset_offset))
      if band(flags_and_frag_offset, flag_dont_fragment_mask) ~= 0 then
         return FRAGMENT_FORBIDDEN, nil
      end
   end

   local ihl = get_ihl(ipv4_pkt)
   local header_size = constants.ethernet_header_size + ihl
   local payload_size = ipv4_pkt.length - header_size
   -- Payload bytes per packet must be a multiple of 8
   local payload_bytes_per_packet = band(mtu - header_size, 0xFFF8)
   local total_length_per_packet = payload_bytes_per_packet + ihl
   local num_packets = ceil(payload_size / payload_bytes_per_packet)

   local pkts = { ipv4_pkt }

   wr16(ipv4_pkt.data + frag_id_offset, C.htons(fresh_frag_id()))
   wr16(ipv4_pkt.data + total_length_offset, C.htons(total_length_per_packet))
   wr16(ipv4_pkt.data + flags_and_frag_offset_offset, C.htons(flag_more_fragments_mask))
   wr16(ipv4_pkt.data + checksum_offset, 0)

   local raw_frag_offset = payload_bytes_per_packet

   for i = 2, num_packets - 1 do
      local frag_pkt = packet.allocate()
      ffi.copy(frag_pkt.data, ipv4_pkt.data, header_size)
      ffi.copy(frag_pkt.data + header_size,
               ipv4_pkt.data + header_size + raw_frag_offset,
               payload_bytes_per_packet)
      wr16(frag_pkt.data + flags_and_frag_offset_offset,
           C.htons(bor(flag_more_fragments_mask,
                       band(frag_offset_field_mask, raw_frag_offset / 8))))
      wr16(frag_pkt.data + checksum_offset,
           C.htons(ipsum(frag_pkt.data + ver_and_ihl_offset, ihl, 0)))
      frag_pkt.length = header_size + payload_bytes_per_packet
      raw_frag_offset = raw_frag_offset + payload_bytes_per_packet
      pkts[i] = frag_pkt
   end

   -- Last packet
   local last_pkt = packet.allocate()
   local last_payload_len = payload_size % payload_bytes_per_packet
   ffi.copy(last_pkt.data, ipv4_pkt.data, header_size)
   ffi.copy(last_pkt.data + header_size,
            ipv4_pkt.data + header_size + raw_frag_offset,
            last_payload_len)
   wr16(last_pkt.data + flags_and_frag_offset_offset,
        C.htons(band(frag_offset_field_mask, raw_frag_offset / 8)))
   wr16(last_pkt.data + total_length_offset, C.htons(last_payload_len + ihl))
   wr16(last_pkt.data + checksum_offset,
        C.htons(ipsum(last_pkt.data + ver_and_ihl_offset, ihl, 0)))
   last_pkt.length = header_size + last_payload_len
   pkts[num_packets] = last_pkt

   -- Truncate the original packet, and update its checksum
   ipv4_pkt.length = header_size + payload_bytes_per_packet
   wr16(ipv4_pkt.data + checksum_offset,
        C.htons(ipsum(ipv4_pkt.data + ver_and_ihl_offset, ihl, 0)))

   return FRAGMENT_OK, pkts
end


function selftest()
   print("selftest: lwaftr.fragmentv4.fragment_ipv4")

   local eth_proto = require("lib.protocol.ethernet")
   local ip4_proto = require("lib.protocol.ipv4")

   -- Makes an IPv4 packet, with Ethernet framing, with a given payload size
   local function make_ipv4_packet(payload_size)
      local pkt = packet.allocate()
      pkt.length = eth_proto:sizeof() + ip4_proto:sizeof() + payload_size
      local eth_header = eth_proto:new_from_mem(pkt.data, pkt.length)
      local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_header:sizeof(),
                                                pkt.length - eth_header:sizeof())
      assert(pkt.length == eth_header:sizeof() + ip4_header:sizeof() + payload_size)

      -- Ethernet header
      eth_header:src(eth_proto:pton("5c:51:4f:8f:aa:ee"))
      eth_header:dst(eth_proto:pton("5c:51:4f:8f:aa:ef"))
      eth_header:type(0x0800) -- IPv4

      -- IPv4 header
      ip4_header:version(4)
      ip4_header:ihl(ip4_header:sizeof() / 4)
      ip4_header:dscp(0)
      ip4_header:ecn(0)
      ip4_header:total_length(ip4_header:sizeof() + payload_size)
      ip4_header:id(0)
      ip4_header:flags(0)
      ip4_header:frag_off(0)
      ip4_header:ttl(15)
      ip4_header:protocol(0xFF)
      ip4_header:src(ip4_proto:pton("192.168.10.10"))
      ip4_header:dst(ip4_proto:pton("192.168.10.20"))
      ip4_header:checksum()

      -- We do not fill up the rest of the packet: random contents works fine
      -- because we are testing IP fragmentation, so there's no need to care
      -- about upper layers.

      return pkt
   end

   local function pkt_payload_size(pkt)
      assert(pkt.length >= (eth_proto:sizeof() + ip4_proto:sizeof()))
      local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_proto:sizeof(),
                                                pkt.length - eth_proto:sizeof())
      local total_length = ip4_header:total_length()
      local ihl = ip4_header:ihl() * 4
      assert(ihl == get_ihl(pkt))
      assert(ihl == ip4_header:sizeof())
      assert(total_length - ihl >= 0)
      assert(total_length == pkt.length - eth_proto:sizeof())
      return total_length - ihl
   end

   local function pkt_frag_offset(pkt)
      assert(pkt.length >= (eth_proto:sizeof() + ip4_proto:sizeof()))
      local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_proto:sizeof(),
                                                pkt.length - eth_proto:sizeof())
      return ip4_header:frag_off() * 8
   end

   local function pkt_total_length(pkt)
      assert(pkt.length >= (eth_proto:sizeof() + ip4_proto:sizeof()))
      local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_proto:sizeof(),
                                                pkt.length - eth_proto:sizeof())
      return ip4_header:total_length()
   end

   local function check_packet_fragment(orig_pkt, frag_pkt, is_last_fragment)
      -- Ethernet fields
      local orig_hdr = eth_proto:new_from_mem(orig_pkt.data, orig_pkt.length)
      local frag_hdr = eth_proto:new_from_mem(frag_pkt.data, frag_pkt.length)
      assert(orig_hdr:src_eq(frag_hdr:src()))
      assert(orig_hdr:dst_eq(frag_hdr:dst()))
      assert(orig_hdr:type() == frag_hdr:type())

      -- IPv4 fields
      orig_hdr = ip4_proto:new_from_mem(orig_pkt.data + eth_proto:sizeof(),
                                        orig_pkt.length - eth_proto:sizeof())
      frag_hdr = ip4_proto:new_from_mem(frag_pkt.data + eth_proto:sizeof(),
                                        frag_pkt.length - eth_proto:sizeof())
      assert(orig_hdr:ihl() == frag_hdr:ihl())
      assert(orig_hdr:dscp() == frag_hdr:dscp())
      assert(orig_hdr:ecn() == frag_hdr:ecn())
      assert(orig_hdr:ttl() == frag_hdr:ttl())
      assert(orig_hdr:protocol() == frag_hdr:protocol())
      assert(orig_hdr:src_eq(frag_hdr:src()))
      assert(orig_hdr:dst_eq(frag_hdr:dst()))

      assert(pkt_payload_size(frag_pkt) == frag_pkt.length - eth_proto:sizeof() - ip4_proto:sizeof())

      if is_last_fragment then
         assert(band(frag_hdr:flags(), 0x1) == 0x0)
      else
         assert(band(frag_hdr:flags(), 0x1) == 0x1)
      end
   end

   -- Packet with 1200 bytes of payload
   local pkt = assert(make_ipv4_packet(1200))

   -- MTU bigger than the packet size
   local code, result = assert(fragment_ipv4(pkt, 1500))
   assert(code == FRAGMENT_UNNEEDED)
   assert(pkt == result)

   -- Keep a copy of the packet, for comparisons
   local orig_pkt = packet.allocate()
   orig_pkt.length = pkt.length
   ffi.copy(orig_pkt.data, pkt.data, pkt.length)

   assert(pkt.length > 1200, "packet short than payload size")

   code, result = assert(fragment_ipv4(pkt, 1000))
   assert(code == FRAGMENT_OK)
   assert(#result == 2, "fragmentation returned " .. #result .. " packets (2 expected)")

   for i = 1, #result do
      assert(result[i].length <= 1000, "packet " .. i .. " longer than MTU")
      local is_last = (i == #result)
      check_packet_fragment(orig_pkt, result[i], is_last)
   end

   assert(pkt_payload_size(result[1]) + pkt_payload_size(result[2]) == 1200)
   assert(pkt_payload_size(result[1]) == pkt_frag_offset(result[2]))

   -- Packet with 1200 bytes of payload, which is fragmented into 4 pieces
   pkt = assert(make_ipv4_packet(1200))

   -- Keep a copy of the packet, for comparisons
   orig_pkt = packet.allocate()
   orig_pkt.length = pkt.length
   ffi.copy(orig_pkt.data, pkt.data, pkt.length)

   code, result = assert(fragment_ipv4(pkt, 400))
   assert(code == FRAGMENT_OK)
   assert(#result == 4,
          "fragmentation returned " .. #result .. " packets (4 expected)")
   for i = 1, #result do
      assert(result[i].length <= 1000, "packet " .. i .. " longer than MTU")
      local is_last = (i == #result)
      check_packet_fragment(orig_pkt, result[i], is_last)
   end

   assert(pkt_payload_size(result[1]) + pkt_payload_size(result[2]) +
          pkt_payload_size(result[3]) + pkt_payload_size(result[4]) == 1200)
   assert(pkt_payload_size(result[1]) == pkt_frag_offset(result[2]))
   assert(pkt_payload_size(result[1]) + pkt_payload_size(result[2]) ==
          pkt_frag_offset(result[3]))
   assert(pkt_payload_size(result[1]) + pkt_payload_size(result[2]) +
          pkt_payload_size(result[3]) == pkt_frag_offset(result[4]))

   -- Try to fragment a packet with the "don't fragment" flag set
   pkt = assert(make_ipv4_packet(1200))
   local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_proto:sizeof(),
                                             pkt.length - eth_proto:sizeof())
   ip4_header:flags(0x2) -- Set "don't fragment"
   code, result = fragment_ipv4(pkt, 500)
   assert(code == FRAGMENT_FORBIDDEN)
   assert(type(result) == "nil")

   -- A 1046 byte packet
   local pattern = { 0xCC, 0xAA, 0xFF, 0xEE, 0xBB, 0x11, 0xDD }
   local function pattern_fill(array, length)
      for i = 0, length-1 do
         array[i] = pattern[(i % #pattern) + 1]
      end
   end
   local function pattern_check(array, length)
      for i = 0, length-1 do
         assert(array[i], pattern[(i % #pattern) + 1], "pos: " .. i)
      end
   end

   pkt = make_ipv4_packet(1046 - ip4_proto:sizeof() - eth_proto:sizeof())
   pattern_fill(pkt.data + ip4_proto:sizeof() + eth_proto:sizeof(),
                pkt.length - ip4_proto:sizeof() - eth_proto:sizeof())
   orig_pkt = packet.allocate()
   ffi.copy(orig_pkt.data, pkt.data, pkt.length)

   code, result = fragment_ipv4(pkt, 520)
   assert(code == FRAGMENT_OK)
   assert(#result == 3)

   assert(pkt_payload_size(result[1]) + pkt_payload_size(result[2]) +
          pkt_payload_size(result[3]) == 1046 - ip4_proto:sizeof() - eth_proto:sizeof())

   local size = pkt_payload_size(result[1]) + pkt_payload_size(result[2]) + pkt_payload_size(result[3])
   local data = ffi.new("uint8_t[?]", size)

   for i = 1, #result do
      ffi.copy(data + pkt_frag_offset(result[i]),
               result[i].data + eth_proto:sizeof() + get_ihl(result[i]),
               pkt_payload_size(result[i]))
   end
   pattern_check(data, size)
end
