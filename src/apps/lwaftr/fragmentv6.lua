module(..., package.seeall)

local constants = require("apps.lwaftr.constants")
local lwutil = require("apps.lwaftr.lwutil")

local packet = require("core.packet")
local bit = require("bit")
local ffi = require("ffi")

local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local C = ffi.C
local rd16, rd32, wr16, wr32 = lwutil.rd16, lwutil.rd32, lwutil.wr16, lwutil.wr32
local htons, htonl = lwutil.htons, lwutil.htonl
local ntohs, ntohl = htons, htonl

REASSEMBLY_OK = 1
FRAGMENT_MISSING = 2
REASSEMBLY_INVALID = 3

local dgram

function is_fragment(pkt, l2_size)
   return pkt.data[l2_size + constants.o_ipv6_next_header] == constants.ipv6_frag
end

function get_frag_id(pkt, l2_size)
   local frag_id_start = l2_size + constants.ipv6_fixed_header_size + constants.o_ipv6_frag_id
   return ntohl(rd32(pkt.data + frag_id_start))
end

local function get_frag_len(pkt, l2_size)
   local ipv6_payload_len = l2_size + constants.o_ipv6_payload_len
   return ntohs(rd16(pkt.data + ipv6_payload_len)) - constants.ipv6_frag_header_size
end

-- This is the 'M' bit of the IPv6 fragment header, in the
-- least significant bit of the 4th byte
local function is_last_fragment(frag, l2_size)
   local ipv6_frag_more_offset = l2_size + constants.ipv6_fixed_header_size + 3
   return band(frag.data[ipv6_frag_more_offset], 1) == 0
end

local function get_frag_offset(frag, l2_size)
   -- Layout: 8 fragment offset bits, 5 fragment offset bits, 2 reserved bits, 'M'ore-frags-expected bit
   local ipv6_frag_offset_offset = l2_size + constants.ipv6_fixed_header_size + constants.o_ipv6_frag_offset
   local raw_frag_offset = rd16(frag.data + ipv6_frag_offset_offset)
   return band(ntohs(raw_frag_offset), 0xfffff8)
end

-- IPv6 reassembly, as per https://tools.ietf.org/html/rfc2460#section-4.5
-- with RFC 5722's recommended exclusion of overlapping packets.

-- This frees the fragments if reassembly is completed successfully
-- or known to be invalid, and leaves them alone if fragments
-- are still missing.

-- TODO: handle the 60-second timeout, and associated ICMP iff the fragment
-- with offset 0 was received
-- TODO: handle silently discarding fragments that arrive later if
-- an overlapping fragment was detected (keep a list for a few minutes?)
-- TODO: send ICMP parameter problem code 0 if needed, as per RFC2460
-- (if the fragment's data isn't a multiple of 8 octets and M=1, or
-- if the length of the reassembled packet would exceed 65535 octets)
-- TODO: handle packets of > 10240 octets correctly...
-- TODO: test every branch of this

local lwdebug = require("apps.lwaftr.lwdebug")
local function _reassemble_validated(fragments, fragment_offsets, fragment_lengths, l2_size)
   local repkt = packet.allocate()
   -- The first byte of the fragment header is the next header type
   local first_fragment = fragments[1]
   local ipv6_next_header = first_fragment.data[l2_size + constants.ipv6_fixed_header_size]
 
   -- Copy the original headers; this automatically does the right thing in the face of vlans.
   local fixed_headers_size = l2_size + constants.ipv6_fixed_header_size
   ffi.copy(repkt.data, first_fragment, l2_size + constants.ipv6_fixed_header_size)
   -- Update the next header; it's not a fragment anymore
   repkt.data[l2_size + constants.o_ipv6_next_header] = ipv6_next_header

   local frag_indata_start = l2_size + constants.ipv6_fixed_header_size + constants.ipv6_frag_header_size
   local frag_outdata_start = l2_size + constants.ipv6_fixed_header_size

   for i = 1, #fragments do
      ffi.copy(repkt.data + frag_outdata_start + fragment_offsets[i], fragments[i].data + frag_indata_start, fragment_lengths[i])
   end
   repkt.length = fixed_headers_size + fragment_offsets[#fragments] + fragment_lengths[#fragments]
   return REASSEMBLY_OK, repkt
end

function reassemble(fragments, l2_size)
   local function compare_fragment_offsets(pkt1, pkt2)
      local ipv6_frag_offset_offset = l2_size + constants.ipv6_fixed_header_size + constants.o_ipv6_frag_offset
      return pkt1.data[ipv6_frag_offset_offset] < pkt2.data[ipv6_frag_offset_offset]
   end
   table.sort(fragments, compare_fragment_offsets)

   local status
   local fragment_offsets = {}
   local fragment_lengths = {}
   local reassembled_size = l2_size + constants.ipv6_fixed_header_size
   local err_pkt
   local frag_id
   if get_frag_offset(fragments[1], l2_size) ~= 0 then
      return FRAGMENT_MISSING
   else
      fragment_offsets[1] = 0
      fragment_lengths[1] = get_frag_len(fragments[1], l2_size)
      frag_id = get_frag_id(fragments[1], l2_size)
   end
   for i = 2, #fragments do
      local frag_size = get_frag_offset(fragments[i], l2_size)
      fragment_offsets[i] = frag_size
      local plen = get_frag_len(fragments[i], l2_size)
      fragment_lengths[i] = plen
      reassembled_size = reassembled_size + plen
      if frag_size % 8 ~= 0 and not is_last_fragment(fragments[i], l2_size) then
         -- TODO: send ICMP error code; this is an RFC should
         status = REASSEMBLY_INVALID
      end
      if reassembled_size > constants.ipv6_max_packet_size then
         -- TODO: send ICMP error code
         status = REASSEMBLY_INVALID
      end
      if frag_id ~= get_frag_id(fragments[i], l2_size) then
         -- This function should never be called with fragment IDs that don't all correspond, but just in case...
         status = REASSEMBLY_INVALID
      end

      if fragment_offsets[i] ~= fragment_offsets[i - 1] + fragment_lengths[i - 1] then
         if fragment_offsets[i] > fragment_offsets[i - 1] + fragment_lengths[i - 1] then
            return FRAGMENT_MISSING
         else
            return REASSEMBLY_INVALID -- this prohibits overlapping fragments
         end
      end
   end
   if not is_last_fragment(fragments[#fragments], l2_size) then
      return FRAGMENT_MISSING
   end

   if status == REASSEMBLY_INVALID then
      for i = 1, #fragments do
         packet.free(fragments[i])
      end
      return REASSEMBLY_INVALID, err_pkt
   end
   -- It appears that there's a valid and complete set of fragments.
   return _reassemble_validated(fragments, fragment_offsets, fragment_lengths, l2_size)
end

-- IPv6 fragmentation, as per https://tools.ietf.org/html/rfc5722

-- TODO: consider security/performance tradeoffs of randomization
local internal_frag_id = 0x42424242
local function fresh_frag_id()
   internal_frag_id = band(internal_frag_id + 1, 0xffffffff)
   return internal_frag_id
end

local function write_frag_header(pkt_data, unfrag_header_size, next_header,
                                      frag_offset, more_frags, frag_id)
   pkt_data[unfrag_header_size] = next_header
   pkt_data[unfrag_header_size + 1] = 0 -- Reserved; 0 by specification
   -- 2 bytes: 13 bits frag_offset, 2 0 reserved bits, 'M' (more_frags)
   -- The frag_offset represents 8-octet chunks.
   -- M is 1 iff more packets from the same fragmentable data are expected
   frag_offset = frag_offset / 8
   pkt_data[unfrag_header_size + 2] = rshift(frag_offset, 5)
   pkt_data[unfrag_header_size + 3] = bor(lshift(band(frag_offset, 0x1f), 3), more_frags)
   local base = pkt_data + unfrag_header_size
   wr32(base + 4,  htonl(frag_id))
end

-- TODO: enforce a lower bound mtu of 1280, as per the spec?
-- Packets have two parts: an 'unfragmentable' set of headers, and a
-- fragmentable payload.
function fragment(ipv6_pkt, unfrag_header_size, l2_size, mtu)
   if ipv6_pkt.length - l2_size <= mtu then
      return ipv6_pkt -- No fragmentation needed
   end
   l2_mtu = mtu + l2_size

   local ipv6_payload_len = l2_size + constants.o_ipv6_payload_len
   local more = 1
   -- TODO: carefully evaluate the boundary conditions here
   local new_header_size = unfrag_header_size + constants.ipv6_frag_header_size
   local payload_size = ipv6_pkt.length - unfrag_header_size
   -- Payload bytes per packet must be a multiple of 8
   local payload_bytes_per_packet = band(l2_mtu - new_header_size, 0xfff8)
   local num_packets = math.ceil(payload_size / payload_bytes_per_packet)

   local pkts = {ipv6_pkt}
   local frag_data_start = ipv6_pkt.data + unfrag_header_size
   -- Shift the packet contents to make room for the fragment header
   C.memmove(frag_data_start + constants.ipv6_frag_header_size, frag_data_start, payload_size)
   -- The following assumes the incoming packet had no IPv6 extension headers
   -- which is a valid assumption for IPv6 encapsulation done by the lwaftr
   local next_header_idx = unfrag_header_size - 34 -- 33 bytes = IPv6 src, dst, hop limit
   local fnext_header = ipv6_pkt.data[next_header_idx]
   local frag_id = fresh_frag_id()
   write_frag_header(ipv6_pkt.data, unfrag_header_size, fnext_header, 0, more, frag_id)
   ipv6_pkt.data[next_header_idx] = constants.ipv6_frag
   wr16(ipv6_pkt.data + l2_size + constants.o_ipv6_payload_len,
        htons(payload_bytes_per_packet + constants.ipv6_frag_header_size))
   local raw_frag_offset = payload_bytes_per_packet

   for i=2,num_packets - 1 do
      local frag_pkt = packet.allocate()
      ffi.copy(frag_pkt.data, ipv6_pkt.data, unfrag_header_size)
      write_frag_header(frag_pkt.data, unfrag_header_size, fnext_header,
                             raw_frag_offset, more, frag_id)
      ffi.copy(frag_pkt.data + new_header_size,
               ipv6_pkt.data + new_header_size + raw_frag_offset,
               payload_bytes_per_packet)
      raw_frag_offset = raw_frag_offset + payload_bytes_per_packet
      frag_pkt.length = new_header_size + payload_bytes_per_packet
      pkts[i] = frag_pkt
   end

   -- last packet
   local last_pkt = packet.allocate()
   more = 0
   ffi.copy(last_pkt.data, ipv6_pkt.data, unfrag_header_size)
   write_frag_header(last_pkt.data, unfrag_header_size, fnext_header,
            raw_frag_offset, more, frag_id)
   local last_payload_len = payload_size % payload_bytes_per_packet
   ffi.copy(last_pkt.data + new_header_size,
            ipv6_pkt.data + new_header_size + raw_frag_offset,
            last_payload_len)
   wr16(last_pkt.data + l2_size + constants.o_ipv6_payload_len,
        htons(last_payload_len + constants.ipv6_frag_header_size))
   last_pkt.length = new_header_size + last_payload_len
   pkts[num_packets] = last_pkt

   ipv6_pkt.length = new_header_size + payload_bytes_per_packet -- Truncate the original packet
   return pkts
end
