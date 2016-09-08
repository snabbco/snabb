module(..., package.seeall)

local arp = require("apps.lwaftr.arp")
local constants = require("apps.lwaftr.constants")
local fragmentv4 = require("apps.lwaftr.fragmentv4")
local fragv4_h = require("apps.lwaftr.fragmentv4_hardened")
local lwutil = require("apps.lwaftr.lwutil")
local icmp = require("apps.lwaftr.icmp")

local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")
local checksum = require("lib.checksum")
local packet = require("core.packet")
local bit = require("bit")
local ffi = require("ffi")
local lib = require("core.lib")
local counter = require("core.counter")

local receive, transmit = link.receive, link.transmit
local rd16, wr16, rd32, wr32 = lwutil.rd16, lwutil.wr16, lwutil.rd32, lwutil.wr32
local get_ihl_from_offset, htons = lwutil.get_ihl_from_offset, lwutil.htons
local is_ipv4 = lwutil.is_ipv4
local ntohs = lib.ntohs
local band = bit.band

local n_ethertype_ipv4 = constants.n_ethertype_ipv4
local o_ipv4_identification = constants.o_ipv4_identification
local o_ipv4_src_addr = constants.o_ipv4_src_addr
local o_ipv4_dst_addr = constants.o_ipv4_dst_addr
local o_ethernet_ethertype = constants.o_ethernet_ethertype
local o_ipv4_flags = constants.o_ipv4_flags

local ehs = constants.ethernet_header_size
local o_ipv4_ver_and_ihl = ehs + constants.o_ipv4_ver_and_ihl
local o_ipv4_checksum = ehs + constants.o_ipv4_checksum
local o_icmpv4_msg_type_sans_ihl = ehs + constants.o_icmpv4_msg_type
local o_icmpv4_checksum_sans_ihl = ehs + constants.o_icmpv4_checksum
local icmpv4_echo_request = constants.icmpv4_echo_request
local icmpv4_echo_reply = constants.icmpv4_echo_reply

Reassembler = {}
Fragmenter = {}
ARP = {}
ICMPEcho = {}

function Reassembler:new(conf)
   local max_ipv4_reassembly_packets = assert(conf.max_ipv4_reassembly_packets)
   local max_fragments_per_reassembly_packet = assert(conf.max_fragments_per_reassembly_packet)
   local o = {
      counters = assert(conf.counters, "Counters not initialized"),
      ctab = fragv4_h.initialize_frag_table(max_ipv4_reassembly_packets,
         max_fragments_per_reassembly_packet),
   }
   counter.set(o.counters["memuse-ipv4-frag-reassembly-buffer"],
               o.ctab:get_backing_size())
   return setmetatable(o, {__index=Reassembler})
end

local function is_fragment(pkt)
   -- Either the packet has the "more fragments" flag set,
   -- or the fragment offset is non-zero, or both.
   local flag_more_fragments_mask = 0x2000
   local non_zero_offset = 0x1FFF
   local flags_and_frag_offset = ntohs(rd16(pkt.data + ehs + o_ipv4_flags))
   return band(flags_and_frag_offset, flag_more_fragments_mask) ~= 0 or
      band(flags_and_frag_offset, non_zero_offset) ~= 0
end

function Reassembler:cache_fragment(fragment)
   return fragv4_h.cache_fragment(self.ctab, fragment)
end

function Reassembler:push ()
   local input, output = self.input.input, self.output.output
   local errors = self.output.errors

   local l2_size = self.l2_size
   local ethertype_offset = self.ethertype_offset

   for _=1,math.min(link.nreadable(input), link.nwritable(output)) do
      local pkt = receive(input)
      if is_ipv4(pkt) and is_fragment(pkt) then
         counter.add(self.counters["in-ipv4-frag-needs-reassembly"])
         local status, maybe_pkt, ejected = self:cache_fragment(pkt)
         if ejected then
            counter.add(self.counters["drop-ipv4-frag-random-evicted"])
         end

         if status == fragv4_h.REASSEMBLY_OK then -- Reassembly was successful
            counter.add(self.counters["in-ipv4-frag-reassembled"])
            transmit(output, maybe_pkt)
         elseif status == fragv4_h.FRAGMENT_MISSING then -- Nothing to do, wait.
         elseif status == fragv4_h.REASSEMBLY_INVALID then
            counter.add(self.counters["drop-ipv4-frag-invalid-reassembly"])
            if maybe_pkt then -- This is an ICMP packet
               transmit(errors, maybe_pkt)
            end
         else -- unreachable
            packet.free(pkt)
         end
      else
         -- Forward all packets that aren't IPv4 fragments.
         counter.add(self.counters["in-ipv4-frag-reassembly-unneeded"])
         transmit(output, pkt)
      end
   end
end

function Fragmenter:new(conf)
   local o = {
      counters = assert(conf.counters, "Counters not initialized"),
      mtu = assert(conf.mtu),
   }
   return setmetatable(o, {__index=Fragmenter})
end

function Fragmenter:push ()
   local input, output = self.input.input, self.output.output

   local mtu = self.mtu

   for _=1,link.nreadable(input) do
      local pkt = receive(input)
      if pkt.length > mtu + ehs and is_ipv4(pkt) then
         local status, frags = fragmentv4.fragment(pkt, mtu)
         if status == fragmentv4.FRAGMENT_OK then
            for i=1,#frags do
               counter.add(self.counters["out-ipv4-frag"])
               transmit(output, frags[i])
            end
         else
            -- TODO: send ICMPv4 info if allowed by policy
            packet.free(pkt)
         end
      else
         counter.add(self.counters["out-ipv4-frag-not"])
         transmit(output, pkt)
      end
   end
end

function ARP:new(conf)
   local o = setmetatable({}, {__index=ARP})
   o.conf = conf
   -- TODO: verify that the src and dst ipv4 addresses and src mac address
   -- have been provided, in pton format.
   if not conf.dst_eth then
      o.arp_request_pkt = arp.form_request(conf.src_eth, conf.src_ipv4, conf.dst_ipv4)
      self.arp_request_interval = 3 -- Send a new arp_request every three seconds.
      self.arp_request_max_retries = 5 -- Max number of arp_request retries.
      self.arp_request_retries = 0
   end
   o.dst_eth = conf.dst_eth -- intentionally nil if to request via ARP
   return o
end

function ARP:maybe_send_arp_request (output)
   if self.dst_eth then return end
   if self.arp_request_retries == self.arp_request_max_retries then
      error(("Could not resolve IPv4 address: %s"):format(
         ipv4:ntop(self.conf.dst_ipv4)))
   end
   self.next_arp_request_time = self.next_arp_request_time or engine.now()
   if self.next_arp_request_time <= engine.now() then
      self:send_arp_request(output)
      self.next_arp_request_time = engine.now() + self.arp_request_interval
      self.arp_request_retries = self.arp_request_retries + 1
   end
end

function ARP:send_arp_request (output)
   transmit(output, packet.clone(self.arp_request_pkt))
end

function ARP:push()
   local isouth, osouth = self.input.south, self.output.south
   local inorth, onorth = self.input.north, self.output.north

   self:maybe_send_arp_request(osouth)

   for _=1,link.nreadable(isouth) do
      local p = receive(isouth)
      if arp.is_arp(p) then
         if not self.dst_eth and arp.is_arp_reply(p) then
            local dst_ethernet = arp.get_isat_ethernet(p, self.conf.dst_ipv4)
            if dst_ethernet then
               self.dst_eth = dst_ethernet
            end
            packet.free(p)
         elseif arp.is_arp_request(p, self.conf.src_ipv4) then
            local arp_reply_pkt = arp.form_reply(self.conf.src_eth, self.conf.src_ipv4, p)
            if arp_reply_pkt then
               transmit(osouth, arp_reply_pkt)
            end
            packet.free(p)
         else -- incoming ARP that isn't handled; drop it silently
            packet.free(p)
         end
      else
         transmit(onorth, p)
      end
   end

   for _=1,link.nreadable(inorth) do
      local p = receive(inorth)
      if not self.dst_eth then
         -- drop all southbound packets until the next hop's ethernet address is known
         packet.free(p)
      else
         lwutil.set_dst_ethernet(p, self.dst_eth)
         transmit(osouth, p)
      end
   end
end

function ICMPEcho:new(conf)
   local addresses = {}
   if conf.address then
      addresses[rd32(conf.address)] = true
   end
   if conf.addresses then
      for _, v in ipairs(conf.addresses) do
         addresses[rd32(v)] = true
      end
   end
   return setmetatable({addresses = addresses}, {__index = ICMPEcho})
end

function ICMPEcho:push()
   local l_in, l_out, l_reply = self.input.south, self.output.north, self.output.south

   for _ = 1, link.nreadable(l_in) do
      local out, pkt = l_out, receive(l_in)

      if icmp.is_icmpv4_message(pkt, icmpv4_echo_request, 0) then
         local pkt_ipv4 = ipv4:new_from_mem(pkt.data + ehs,
                                            pkt.length - ehs)
         local pkt_ipv4_dst = rd32(pkt_ipv4:dst())
         if self.addresses[pkt_ipv4_dst] then
            ethernet:new_from_mem(pkt.data, ehs):swap()

            -- Swap IP source/destination
            pkt_ipv4:dst(pkt_ipv4:src())
            wr32(pkt_ipv4:src(), pkt_ipv4_dst)

            -- Change ICMP message type
            local ihl = get_ihl_from_offset(pkt, o_ipv4_ver_and_ihl)
            pkt.data[o_icmpv4_msg_type_sans_ihl + ihl] = icmpv4_echo_reply

            -- Clear out flags
            pkt_ipv4:flags(0)

            -- Recalculate checksums
            wr16(pkt.data + o_icmpv4_checksum_sans_ihl + ihl, 0)
            local icmp_offset = ehs + ihl
            local csum = checksum.ipsum(pkt.data + icmp_offset, pkt.length - icmp_offset, 0)
            wr16(pkt.data + o_icmpv4_checksum_sans_ihl + ihl, htons(csum))
            wr16(pkt.data + o_ipv4_checksum, 0)
            pkt_ipv4:checksum()

            out = l_reply
         end
      end

      transmit(out, pkt)
   end

   l_in, l_out = self.input.north, self.output.south
   for _ = 1, link.nreadable(l_in) do
      transmit(l_out, receive(l_in))
   end
end
