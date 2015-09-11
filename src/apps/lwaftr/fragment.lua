module(..., package.seeall)

local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")

--local lwutil = require("apps.lwaftr.lwutil")
local constants = require("apps.lwaftr.constants")
local packet = require("core.packet")
local bit = require("bit")
local ffi = require("ffi")

local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local C = ffi.C

REASSEMBLY_OK = 1
FRAGMENT_MISSING = 2
REASSEMBLY_INVALID = 3

local ipv6_payload_len = constants.ethernet_header_size + constants.ipv6_payload_len
local frag_id_start = constants.ethernet_header_size + constants.ipv6_fixed_header_size + constants.ipv6_frag_id
local ipv6_frag_offset_offset = constants.ethernet_header_size + constants.ipv6_fixed_header_size + constants.ipv6_frag_offset

local dgram = datagram:new()

local function compare_fragment_offsets(pkt1, pkt2)
   return pkt1.data[ipv6_frag_offset_offset] < pkt2.data[ipv6_frag_offset_offset]
end

function is_ipv6_fragment(pkt)
   return pkt.data[constants.ethernet_header_size + constants.ipv6_next_header] == constants.ipv6_frag
end

function get_ipv6_frag_id(pkt)
   return C.ntohl(ffi.cast("uint32_t*", pkt.data + frag_id_start)[0])
end

local function get_ipv6_frag_len(pkt)
   return C.ntohs(ffi.cast("uint16_t*", pkt.data + ipv6_payload_len)[0]) - constants.ipv6_frag_header_size
end

-- This is the 'M' bit of the IPv6 fragment header, in the
-- least significant bit of the 4th byte
local ipv6_frag_more_offset = constants.ethernet_header_size + constants.ipv6_fixed_header_size + 3
local function is_last_fragment(frag)
   return band(frag.data[ipv6_frag_more_offset], 1) == 0
end

local function get_frag_offset(frag)
   -- Layout: 8 fragment offset bits, 5 fragment offset bits, 2 reserved bits, 'M'ore-frags-expected bit
   local raw_frag_offset = ffi.cast("uint16_t*", frag.data + ipv6_frag_offset_offset)[0]
   return band(C.ntohs(raw_frag_offset), 0xfffff8)
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

local function _reassemble_ipv6_validated(fragments, fragment_offsets, fragment_lengths)
   local repkt = packet.allocate()
   -- The first byte of the fragment header is the next header type
   local first_fragment = fragments[1]
   local ipv6_next_header = first_fragment.data[constants.ethernet_header_size + constants.ipv6_fixed_header_size]
   local eth_src = first_fragment.data + constants.ethernet_src_addr
   local eth_dst = first_fragment.data + constants.ethernet_dst_addr
   local ipv6_src = first_fragment.data + constants.ethernet_header_size + constants.ipv6_src_addr
   local ipv6_dst = first_fragment.data + constants.ethernet_header_size + constants.ipv6_dst_addr

   local ipv6_header = ipv6:new({next_header = ipv6_next_header, hop_limit = constants.default_ttl, src = ipv6_src, dst = ipv6_dst})
   local eth_header = ethernet:new({src = eth_src, dst = eth_dst, type = constants.ethertype_ipv6})
   local ipv6_header = ipv6:new({next_header = ipv6_next_header, hop_limit = constants.default_ttl, src = ipv6_src, dst = ipv6_dst})
   local frag_start = constants.ethernet_header_size + constants.ipv6_fixed_header_size

   local dgram = dgram:reuse(repkt)
   dgram:push(ipv6_header)
   dgram:push(eth_header)
   ipv6_header:free()
   eth_header:free()
   local frag_indata_start = constants.ethernet_header_size + constants.ipv6_fixed_header_size + constants.ipv6_frag_header_size
   local frag_outdata_start = constants.ethernet_header_size + constants.ipv6_fixed_header_size
   for i = 1, #fragments do
      ffi.copy(repkt.data + frag_outdata_start + fragment_offsets[i], fragments[i].data + frag_indata_start, fragment_lengths[i])
   end
   repkt.length = repkt.length + fragment_offsets[#fragments] + fragment_lengths[#fragments]
   return REASSEMBLY_OK, repkt
end

function reassemble_ipv6(fragments)
   table.sort(fragments, compare_fragment_offsets)

   local status
   local fragment_offsets = {}
   local fragment_lengths = {}
   local reassembled_size = constants.ethernet_header_size + constants.ipv6_fixed_header_size
   local err_pkt
   local frag_id
   if get_frag_offset(fragments[1]) ~= 0 then
      return FRAGMENT_MISSING
   else
      fragment_offsets[1] = 0
      fragment_lengths[1] = get_ipv6_frag_len(fragments[1])
      frag_id = get_ipv6_frag_id(fragments[1])
   end
   for i = 2, #fragments do
      local frag_size = get_frag_offset(fragments[i])
      fragment_offsets[i] = frag_size
      local plen = get_ipv6_frag_len(fragments[i])
      fragment_lengths[i] = plen
      reassembled_size = reassembled_size + plen
      if frag_size % 8 ~= 0 and not is_last_fragment(fragments[i]) then
         -- TODO: send ICMP error code; this is an RFC should
         status = REASSEMBLY_INVALID
      end
      if reassembled_size > constants.ipv6_max_packet_size then
         -- TODO: send ICMP error code
         status = REASSEMBLY_INVALID
      end
      if frag_id ~= get_ipv6_frag_id(fragments[i]) then
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
   if not is_last_fragment(fragments[#fragments]) then
      return FRAGMENT_MISSING
   end

   if status == REASSEMBLY_INVALID then
      for i = 1, #fragments do
         packet.free(fragments[i])
      end
      return REASSEMBLY_INVALID, err_pkt
   end
   -- It appears that there's a valid and complete set of fragments.
   return _reassemble_ipv6_validated(fragments, fragment_offsets, fragment_lengths)
end

-- IPv6 fragmentation, as per https://tools.ietf.org/html/rfc5722

-- TODO: consider security/performance tradeoffs of randomization
local internal_frag_id = 0x42424242
local function fresh_frag_id()
   internal_frag_id = band(internal_frag_id + 1, 0xffffffff)
   return internal_frag_id
end

local function write_ipv6_frag_header(pkt_data, unfrag_header_size, next_header,
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
   ffi.cast("uint32_t*", base + 4)[0] = C.htonl(frag_id)
end

-- TODO: enforce a lower bound mtu of 1280, as per the spec?
-- Packets have two parts: an 'unfragmentable' set of headers, and a
-- fragmentable payload.
function fragment_ipv6(ipv6_pkt, unfrag_header_size, mtu)
   if ipv6_pkt.length <= mtu then
      return ipv6_pkt -- No fragmentation needed
   end

   local more = 1
   -- TODO: carefully evaluate the boundary conditions here
   local new_header_size = unfrag_header_size + constants.ipv6_frag_header_size
   local payload_size = ipv6_pkt.length - unfrag_header_size
   -- Payload bytes per packet must be a multiple of 8
   local payload_bytes_per_packet = band(mtu - new_header_size, 0xfff8)
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
   write_ipv6_frag_header(ipv6_pkt.data, unfrag_header_size, fnext_header, 0, more, frag_id)
   ipv6_pkt.data[next_header_idx] = constants.ipv6_frag
   ffi.cast("uint16_t*", ipv6_pkt.data + constants.ethernet_header_size + constants.ipv6_payload_len)[0] =
      C.htons(payload_bytes_per_packet + constants.ipv6_frag_header_size)
   local raw_frag_offset = payload_bytes_per_packet

   for i=2,num_packets - 1 do
      local frag_pkt = packet.allocate()
      ffi.copy(frag_pkt.data, ipv6_pkt.data, unfrag_header_size)
      write_ipv6_frag_header(frag_pkt.data, unfrag_header_size, fnext_header,
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
   write_ipv6_frag_header(last_pkt.data, unfrag_header_size, fnext_header,
		     raw_frag_offset, more, frag_id)
   local last_payload_len = payload_size % payload_bytes_per_packet
   ffi.copy(last_pkt.data + new_header_size,
            ipv6_pkt.data + new_header_size + raw_frag_offset,
            last_payload_len)
   ffi.cast("uint16_t*", last_pkt.data + constants.ethernet_header_size + constants.ipv6_payload_len)[0] =
      C.htons(last_payload_len + constants.ipv6_frag_header_size)
   last_pkt.length = new_header_size + last_payload_len
   pkts[num_packets] = last_pkt

   ipv6_pkt.length = new_header_size + payload_bytes_per_packet -- Truncate the original packet
   return pkts
end
