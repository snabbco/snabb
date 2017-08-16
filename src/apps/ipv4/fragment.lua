-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- IPv4 fragmentation (RFC 791)

module(..., package.seeall)

local bit        = require("bit")
local ffi        = require("ffi")
local lib        = require("core.lib")
local packet     = require("core.packet")
local counter    = require("core.counter")
local link       = require("core.link")
local ipsum      = require("lib.checksum").ipsum
local eth_proto  = require("lib.protocol.ethernet")
local ip4_proto  = require("lib.protocol.ipv4")

local constants = require("apps.lwaftr.constants")
local lwutil = require("apps.lwaftr.lwutil")

local receive, transmit = link.receive, link.transmit

local is_ipv4 = lwutil.is_ipv4
local rd16, wr16, get_ihl_from_offset = lwutil.rd16, lwutil.wr16, lwutil.get_ihl_from_offset
local band, bor = bit.band, bit.bor
local ntohs, htons = lib.ntohs, lib.htons
local ceil = math.ceil

local ehs = constants.ethernet_header_size

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

local FRAGMENT_OK = 1
local FRAGMENT_UNNEEDED = 2
local FRAGMENT_FORBIDDEN = 3

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
local function fragment(ipv4_pkt, mtu)
   if ipv4_pkt.length - ehs <= mtu then
      return FRAGMENT_UNNEEDED, ipv4_pkt
   end
   local l2_mtu = mtu + ehs

   local ver_and_ihl_offset = ehs + constants.o_ipv4_ver_and_ihl
   local total_length_offset = ehs + constants.o_ipv4_total_length
   local frag_id_offset = ehs + constants.o_ipv4_identification
   local flags_and_frag_offset_offset = ehs + constants.o_ipv4_flags
   local checksum_offset = ehs + constants.o_ipv4_checksum
   -- Discard packets with the DF (dont't fragment) flag set
   do
      local flags_and_frag_offset = ntohs(rd16(ipv4_pkt.data + flags_and_frag_offset_offset))
      if band(flags_and_frag_offset, flag_dont_fragment_mask) ~= 0 then
         return FRAGMENT_FORBIDDEN, nil
      end
   end

   local ihl = get_ihl_from_offset(ipv4_pkt, ehs)
   local header_size = ehs + ihl
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
   local last_payload_len = payload_size - raw_frag_offset
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

Fragmenter = {}
Fragmenter.shm = {
   ["out-ipv4-frag"]      = {counter},
   ["out-ipv4-frag-not"]  = {counter}
}
local fragmenter_config_params = {
   -- Maximum transmission unit, in bytes, not including the ethernet
   -- header.
   mtu = { mandatory=true }
}

function Fragmenter:new(conf)
   local o = lib.parse(conf, fragmenter_config_params)
   -- RFC 791: "Every internet module must be able to forward a datagram
   -- of 68 octets without further fragmentation.  This is because an
   -- internet header may be up to 60 octets, and the minimum fragment
   -- is 8 octets."
   assert(o.mtu >= 68)
   return setmetatable(o, {__index=Fragmenter})
end

function Fragmenter:push ()
   local input, output = self.input.input, self.output.output
   local mtu = self.mtu

   for _ = 1, link.nreadable(input) do
      local pkt = receive(input)
      if pkt.length > mtu + ehs and is_ipv4(pkt) then
         local status, frags = fragment(pkt, mtu)
         if status == FRAGMENT_OK then
            -- The original packet will be truncated and used as the
            -- first fragment.
            for i=1,#frags do
               counter.add(self.shm["out-ipv4-frag"])
               transmit(output, frags[i])
            end
         else
            -- TODO: send ICMPv4 info if allowed by policy
            packet.free(pkt)
         end
      else
         counter.add(self.shm["out-ipv4-frag-not"])
         transmit(output, pkt)
      end
   end
end

--
-- Returns a new packet, which contains an Ethernet frame, with an IPv4 header,
-- followed by a payload of "payload_size" random bytes.
--
local function make_ipv4_packet(payload_size)
   local eth_size = eth_proto:sizeof()
   local pkt = packet.allocate()
   pkt.length = eth_size + ip4_proto:sizeof() + payload_size
   local eth_header = eth_proto:new_from_mem(pkt.data, pkt.length)
   local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_size,
                                             pkt.length - eth_size)
   assert(pkt.length == eth_size + ip4_header:sizeof() + payload_size)

   -- Ethernet header. The leading bits of the MAC addresses are those for
   -- "Intel Corp" devices, the rest are arbitrary.
   eth_header:src(eth_proto:pton("5c:51:4f:8f:aa:ee"))
   eth_header:dst(eth_proto:pton("5c:51:4f:8f:aa:ef"))
   eth_header:type(constants.ethertype_ipv4)

   -- IPv4 header
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
   local eth_size = eth_proto:sizeof()
   local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_size,
                                             pkt.length - eth_size)
   local total_length = ip4_header:total_length()
   local ihl = ip4_header:ihl() * 4
   assert(ihl == get_ihl_from_offset(pkt, eth_size))
   assert(ihl == ip4_header:sizeof())
   assert(total_length - ihl >= 0)
   assert(total_length == pkt.length - eth_size)
   return total_length - ihl
end

local function pkt_frag_offset(pkt)
   assert(pkt.length >= (eth_proto:sizeof() + ip4_proto:sizeof()))
   local eth_size = eth_proto:sizeof()
   local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_size,
                                             pkt.length - eth_size)
   return ip4_header:frag_off() * 8
end

local function pkt_total_length(pkt)
   assert(pkt.length >= (eth_proto:sizeof() + ip4_proto:sizeof()))
   local eth_size = eth_proto:sizeof()
   local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_size,
                                             pkt.length - eth_size)
   return ip4_header:total_length()
end

--
-- Checks that "frag_pkt" is a valid fragment of the "orig_pkt" packet.
--
local function check_packet_fragment(orig_pkt, frag_pkt, is_last_fragment)
   -- Ethernet fields
   local orig_hdr = eth_proto:new_from_mem(orig_pkt.data, orig_pkt.length)
   local frag_hdr = eth_proto:new_from_mem(frag_pkt.data, frag_pkt.length)
   assert(orig_hdr:src_eq(frag_hdr:src()))
   assert(orig_hdr:dst_eq(frag_hdr:dst()))
   assert(orig_hdr:type() == frag_hdr:type())

   -- IPv4 fields
   local eth_size = eth_proto:sizeof()
   orig_hdr = ip4_proto:new_from_mem(orig_pkt.data + eth_size,
                                     orig_pkt.length - eth_size)
   frag_hdr = ip4_proto:new_from_mem(frag_pkt.data + eth_size,
                                     frag_pkt.length - eth_size)
   assert(orig_hdr:ihl() == frag_hdr:ihl())
   assert(orig_hdr:dscp() == frag_hdr:dscp())
   assert(orig_hdr:ecn() == frag_hdr:ecn())
   assert(orig_hdr:ttl() == frag_hdr:ttl())
   assert(orig_hdr:protocol() == frag_hdr:protocol())
   assert(orig_hdr:src_eq(frag_hdr:src()))
   assert(orig_hdr:dst_eq(frag_hdr:dst()))

   assert(pkt_payload_size(frag_pkt) == frag_pkt.length - eth_size - ip4_proto:sizeof())

   if is_last_fragment then
      assert(band(frag_hdr:flags(), 0x1) == 0x0)
   else
      assert(band(frag_hdr:flags(), 0x1) == 0x1)
   end
end

local function test_payload_1200_mtu_1500()
   print("test:   payload=1200 mtu=1500")

   local pkt = make_ipv4_packet(1200)
   local code, result = fragment(pkt, 1500)
   assert(code == FRAGMENT_UNNEEDED)
   assert(pkt == result)
end

local function test_payload_1200_mtu_1000()
   print("test:   payload=1200 mtu=1000")
   local pkt = make_ipv4_packet(1200)

   -- Keep a copy of the packet, for comparisons
   local orig_pkt = packet.clone(pkt)

   assert(pkt.length > 1200, "packet short than payload size")
   local ehs = constants.ethernet_header_size
   local code, result = fragment(pkt, 1000 - ehs)
   assert(code == FRAGMENT_OK)
   assert(#result == 2, "fragmentation returned " .. #result .. " packets (2 expected)")

   for i = 1, #result do
      assert(result[i].length <= 1000, "packet " .. i .. " longer than MTU")
      local is_last = (i == #result)
      check_packet_fragment(orig_pkt, result[i], is_last)
   end

   assert(pkt_payload_size(result[1]) + pkt_payload_size(result[2]) == 1200)
   assert(pkt_payload_size(result[1]) == pkt_frag_offset(result[2]))
end

local function test_payload_1200_mtu_400()
   print("test:   payload=1200 mtu=400")
   local pkt = make_ipv4_packet(1200)

   -- Keep a copy of the packet, for comparisons
   local orig_pkt = packet.clone(pkt)
   local ehs = constants.ethernet_header_size
   local code, result = fragment(pkt, 400 - ehs)
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
end

local function test_dont_fragment_flag()
   print("test:   packet with \"don't fragment\" flag")
   -- Try to fragment a packet with the "don't fragment" flag set
   local pkt = make_ipv4_packet(1200)
   local ip4_header = ip4_proto:new_from_mem(pkt.data + eth_proto:sizeof(),
                                             pkt.length - eth_proto:sizeof())
   ip4_header:flags(0x2) -- Set "don't fragment"
   local code, result = fragment(pkt, 500)
   assert(code == FRAGMENT_FORBIDDEN)
   assert(type(result) == "nil")
end

function selftest()
   print("selftest: apps.ipv4.fragment")

   test_payload_1200_mtu_1500()
   test_payload_1200_mtu_1000()
   test_payload_1200_mtu_400()
   test_dont_fragment_flag()

   local shm        = require("core.shm")
   local datagram   = require("lib.protocol.datagram")
   local ether      = require("lib.protocol.ethernet")
   local ipv4       = require("lib.protocol.ipv4")
   local Fragmenter = require("apps.ipv4.fragment").Fragmenter

   local ethertype_ipv4 = 0x0800

   local function random_ipv4() return lib.random_bytes(4) end
   local function random_mac() return lib.random_bytes(6) end

   -- Returns a new packet containing an Ethernet frame with an IPv4
   -- header followed by PAYLOAD_SIZE random bytes.
   local function make_test_packet(payload_size, flags)
      local pkt = packet.from_pointer(lib.random_bytes(payload_size),
                                      payload_size)
      local eth_h = ether:new({ src = random_mac(), dst = random_mac(),
                                type = ethertype_ipv4 })
      local ip_h  = ipv4:new({ src = random_ipv4(), dst = random_ipv4(),
                               protocol = 0xff, ttl = 64 })
      ip_h:total_length(ip_h:sizeof() + pkt.length)
      ip_h:flags(flags)
      ip_h:checksum()

      local dgram = datagram:new(pkt)
      dgram:push(ip_h)
      dgram:push(eth_h)
      return dgram:packet()
   end

   local frame = shm.create_frame("apps/fragmenter", Fragmenter.shm)
   local input = link.new('fragment input')
   local output = link.new('fragment output')

   local function fragment(pkt, mtu)
      local fragment = Fragmenter:new({mtu=mtu})
      fragment.shm = frame
      fragment.input, fragment.output = { input = input }, { output = output }
      link.transmit(input, packet.clone(pkt))
      fragment:push()
      local ret = {}
      while not link.empty(output) do
         table.insert(ret, link.receive(output))
      end
      return ret
   end

   -- Correct reassembly is tested in apps.ipv4.reassemble.  Here we
   -- just test that the packet chunks add up to the original size.
   for size = 0, 2000, 7 do
      local pkt = make_test_packet(size, 0)
      for mtu = 68, 2500, 3 do
         local fragments = fragment(pkt, mtu)
         local payload_size = 0
         for i, p in ipairs(fragments) do
            assert(p.length >= ehs + ipv4:sizeof())
            local ipv4 = ipv4:new_from_mem(p.data + ehs,
                                           p.length - ehs)
            assert(p.length == ehs + ipv4:total_length())
            local this_payload_size = p.length - ipv4:sizeof() - ehs
            payload_size = payload_size + this_payload_size
            packet.free(p)
         end
         assert(size == payload_size)
      end
      packet.free(pkt)
   end

   shm.delete_frame(frame)
   link.free(input, 'fragment input')
   link.free(output, 'fragment output')

   print("selftest: ok")
end
