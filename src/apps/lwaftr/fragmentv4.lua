module(..., package.seeall)

local constants = require("apps.lwaftr.constants")
local lwutil = require("apps.lwaftr.lwutil")
local packet = require("core.packet")
local ipsum = require("lib.checksum").ipsum
local bit = require("bit")
local ffi = require("ffi")

local rd16, wr16, wr32, get_ihl_from_offset = lwutil.rd16, lwutil.wr16, lwutil.wr32, lwutil.get_ihl_from_offset
local cast = ffi.cast
local htons, htonl = lwutil.htons, lwutil.htonl
local ntohs, ntohl = htons, htonl
local band, bor = bit.band, bit.bor
local ceil = math.ceil

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
--     is modified in-place. Note that the MTU is for layer 3, excluding
--     L2 ethernet/vlan headers.
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
function fragment(ipv4_pkt, l2_size, mtu)
   if ipv4_pkt.length - l2_size <= mtu then
      return FRAGMENT_UNNEEDED, ipv4_pkt
   end
   l2_mtu = mtu + l2_size

   local ver_and_ihl_offset = l2_size + constants.o_ipv4_ver_and_ihl
   local total_length_offset = l2_size + constants.o_ipv4_total_length
   local frag_id_offset = l2_size + constants.o_ipv4_identification
   local flags_and_frag_offset_offset = l2_size + constants.o_ipv4_flags
   local checksum_offset = l2_size + constants.o_ipv4_checksum
   -- Discard packets with the DF (dont't fragment) flag set
   do
      local flags_and_frag_offset = ntohs(rd16(ipv4_pkt.data + flags_and_frag_offset_offset))
      if band(flags_and_frag_offset, flag_dont_fragment_mask) ~= 0 then
         return FRAGMENT_FORBIDDEN, nil
      end
   end

   local ihl = get_ihl_from_offset(ipv4_pkt, l2_size)
   local header_size = l2_size + ihl
   local payload_size = ipv4_pkt.length - header_size
   -- Payload bytes per packet must be a multiple of 8
   local payload_bytes_per_packet = band(l2_mtu - header_size, 0xFFF8)
   local total_length_per_packet = payload_bytes_per_packet + ihl
   local num_packets = ceil(payload_size / payload_bytes_per_packet)

   local pkts = { ipv4_pkt }

   wr16(ipv4_pkt.data + frag_id_offset, htons(fresh_frag_id()))
   wr16(ipv4_pkt.data + total_length_offset, htons(total_length_per_packet))
   wr16(ipv4_pkt.data + flags_and_frag_offset_offset, htons(flag_more_fragments_mask))
   wr16(ipv4_pkt.data + checksum_offset, 0)

   local raw_frag_offset = payload_bytes_per_packet

   for i = 2, num_packets - 1 do
      local frag_pkt = packet.allocate()
      ffi.copy(frag_pkt.data, ipv4_pkt.data, header_size)
      ffi.copy(frag_pkt.data + header_size,
               ipv4_pkt.data + header_size + raw_frag_offset,
               payload_bytes_per_packet)
      wr16(frag_pkt.data + flags_and_frag_offset_offset,
           htons(bor(flag_more_fragments_mask,
                       band(frag_offset_field_mask, raw_frag_offset / 8))))
      wr16(frag_pkt.data + checksum_offset,
           htons(ipsum(frag_pkt.data + ver_and_ihl_offset, ihl, 0)))
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
        htons(band(frag_offset_field_mask, raw_frag_offset / 8)))
   wr16(last_pkt.data + total_length_offset, htons(last_payload_len + ihl))
   wr16(last_pkt.data + checksum_offset,
        htons(ipsum(last_pkt.data + ver_and_ihl_offset, ihl, 0)))
   last_pkt.length = header_size + last_payload_len
   pkts[num_packets] = last_pkt

   -- Truncate the original packet, and update its checksum
   ipv4_pkt.length = header_size + payload_bytes_per_packet
   wr16(ipv4_pkt.data + checksum_offset,
        htons(ipsum(ipv4_pkt.data + ver_and_ihl_offset, ihl, 0)))

   return FRAGMENT_OK, pkts
end


function is_fragment(pkt, l2_size)
   -- Either the packet has the "more fragments" flag set,
   -- or the fragment offset is non-zero, or both.
   local flags_and_frag_offset = ntohs(rd16(pkt.data + l2_size + constants.o_ipv4_flags))
   return band(flags_and_frag_offset, flag_more_fragments_mask) ~= 0 or
      band(flags_and_frag_offset, frag_offset_field_mask) ~= 0
end


REASSEMBLE_OK = 1
REASSEMBLE_INVALID = 2
REASSEMBLE_MISSING_FRAGMENT = 3


function reassemble(fragments, l2_size)
   local flags_and_frag_offset_offset = l2_size + constants.o_ipv4_flags
   table.sort(fragments, function (pkt1, pkt2)
       local pkt1_offset = band(ntohs(rd16(pkt1.data + flags_and_frag_offset_offset)),
                                frag_offset_field_mask)
       local pkt2_offset = band(ntohs(rd16(pkt2.data + flags_and_frag_offset_offset)),
                                frag_offset_field_mask)
       return pkt1_offset < pkt2_offset
   end)

   -- Check that first fragment has a 0 as fragment offset.
   if band(ntohs(rd16(fragments[1].data + flags_and_frag_offset_offset)),
           frag_offset_field_mask) ~= 0
   then
      return REASSEMBLE_MISSING_FRAGMENT
   end

   -- Check that the last fragment does not have "more fragments" flag set
   if band(ntohs(rd16(fragments[#fragments].data + flags_and_frag_offset_offset)),
           flag_more_fragments_mask) ~= 0
   then
      return REASSEMBLE_MISSING_FRAGMENT
   end

   local ihl = get_ihl_from_offset(fragments[1], l2_size)
   local header_size = l2_size + ihl
   local frag_id_offset = l2_size + constants.o_ipv4_identification
   local frag_id = rd16(fragments[1].data + frag_id_offset)
   local packet_size = fragments[1].length
   local fragment_lengths = { packet_size - header_size }
   local fragment_offsets = { 0 }
   local status = REASSEMBLE_OK

   for i = 2, #fragments do
      local fragment = fragments[i]

      -- Check whether:
      --   1. All fragmented packets have the same IHL
      --   2. Fragmented packets have the same identification
      if get_ihl_from_offset(fragment, l2_size) ~= ihl or
         rd16(fragment.data + frag_id_offset) ~= frag_id
      then
         status = REASSEMBLE_INVALID
         break
      end

      --   3. The "more fragments" flag is set (except for last fragment)
      local flags_and_frag_offset = ntohs(rd16(fragment.data + flags_and_frag_offset_offset))
      if band(flags_and_frag_offset, flag_more_fragments_mask) == 0 then
         if i ~= #fragments then
            status = REASSEMBLE_INVALID
            break
         end
      end

      --   4. The offset of the fragment matches the expected one
      fragment_lengths[i] = fragment.length - header_size
      fragment_offsets[i] = band(flags_and_frag_offset, frag_offset_field_mask) * 8
      if fragment_offsets[i] ~= fragment_offsets[i - 1] + fragment_lengths[i - 1] then
         if fragment_offsets[i] > fragment_offsets[i - 1] + fragment_lengths[i - 1] then
            return REASSEMBLE_MISSING_FRAGMENT
         end

         -- TODO: Handle overlapping fragments
         status = REASSEMBLE_INVALID
         break
      end

      --   5. The resulting packet size does not exceed the maximum
      packet_size = packet_size + fragment_lengths[i]

      if packet_size > constants.ipv4_max_packet_size then
         status = REASSEMBLE_INVALID
         break
      end
   end

   if status == REASSEMBLE_INVALID then
      for _, fragment in ipairs(fragments) do
         packet.free(fragment)
      end
      return REASSEMBLE_INVALID
   end

   -- We have all the fragments and they are valid, we can now reassemble.
   local pkt = packet.allocate()
   ffi.copy(pkt.data, fragments[1].data, header_size)
   for i = 1, #fragments do
      ffi.copy(pkt.data + header_size + fragment_offsets[i],
               fragments[i].data + header_size,
               fragment_lengths[i])
   end
   pkt.length = packet_size

   -- Set the total length field
   local total_length_offset = l2_size + constants.o_ipv4_total_length
   wr16(pkt.data + total_length_offset, htons(packet_size - header_size + ihl))

   -- Clear fragmentation flags and offset, and fragmentation id
   wr32(pkt.data + frag_id_offset, 0)

   -- Recalculate IP header checksum.
   local ver_and_ihl_offset = l2_size + constants.o_ipv4_ver_and_ihl
   local checksum_offset = l2_size + constants.o_ipv4_checksum
   wr16(pkt.data + checksum_offset, 0)
   wr16(pkt.data + checksum_offset,
        htons(ipsum(pkt.data + ver_and_ihl_offset, ihl, 0)))

   return REASSEMBLE_OK, pkt
end
