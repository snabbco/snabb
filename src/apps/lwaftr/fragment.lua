module(..., package.seeall)

--local lwutil = require("apps.lwaftr.lwutil")
local constants = require("apps.lwaftr.constants")
local packet = require("core.packet")
local ffi = require("ffi")
local C = ffi.C

-- IPv6 fragmentation, as per https://tools.ietf.org/html/rfc5722

-- TODO: consider security/performance tradeoffs of randomization
local internal_frag_id = 0x42424242
local function fresh_frag_id()
   internal_frag_id = bit.band(internal_frag_id + 1, 0xffffffff)
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
   pkt_data[unfrag_header_size + 2] = bit.rshift(frag_offset, 5)
   pkt_data[unfrag_header_size + 3] = bit.bor(bit.lshift(bit.band(0x1f, frag_offset), 3), more_frags)
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
   local payload_bytes_per_packet = bit.band(0xfff8, mtu - new_header_size)
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
   last_pkt.length = new_header_size + last_payload_len
   pkts[num_packets] = last_pkt

   ipv6_pkt.length = new_header_size + payload_bytes_per_packet -- Truncate the original packet
   return pkts
end
