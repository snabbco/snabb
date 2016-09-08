module(..., package.seeall)

local constants = require("apps.lwaftr.constants")
local fragmentv6 = require("apps.lwaftr.fragmentv6")
local fragv6_h = require("apps.lwaftr.fragmentv6_hardened")
local ndp = require("apps.lwaftr.ndp")
local lwutil = require("apps.lwaftr.lwutil")
local icmp = require("apps.lwaftr.icmp")

local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local checksum = require("lib.checksum")
local packet = require("core.packet")
local counter = require("core.counter")

local bit = require("bit")
local ffi = require("ffi")
local C = ffi.C

local receive, transmit = link.receive, link.transmit
local rd16, wr16, htons = lwutil.rd16, lwutil.wr16, lwutil.htons

local ipv6_fixed_header_size = constants.ipv6_fixed_header_size
local n_ethertype_ipv6 = constants.n_ethertype_ipv6
local o_ipv6_src_addr = constants.o_ipv6_src_addr
local o_ipv6_dst_addr = constants.o_ipv6_dst_addr

local proto_icmpv6 = constants.proto_icmpv6
local ethernet_header_size = constants.ethernet_header_size
local o_ethernet_ethertype = constants.o_ethernet_ethertype
local o_icmpv6_header = ethernet_header_size + ipv6_fixed_header_size
local o_icmpv6_msg_type = o_icmpv6_header + constants.o_icmpv6_msg_type
local o_icmpv6_checksum = o_icmpv6_header + constants.o_icmpv6_checksum
local icmpv6_echo_request = constants.icmpv6_echo_request
local icmpv6_echo_reply = constants.icmpv6_echo_reply
local ehs = constants.ethernet_header_size

ReassembleV6 = {}
Fragmenter = {}
NDP = {}
ICMPEcho = {}

function ReassembleV6:new(conf)
   local max_ipv6_reassembly_packets = conf.max_ipv6_reassembly_packets
   local max_fragments_per_reassembly_packet = conf.max_fragments_per_reassembly_packet
   local o = {
      counters = assert(conf.counters, "Counters not initialized"),
      ctab = fragv6_h.initialize_frag_table(max_ipv6_reassembly_packets,
         max_fragments_per_reassembly_packet),
   }
   counter.set(o.counters["memuse-ipv6-frag-reassembly-buffer"],
               o.ctab:get_backing_size())
   return setmetatable(o, {__index = ReassembleV6})
end

function ReassembleV6:cache_fragment(fragment)
   return fragv6_h.cache_fragment(self.ctab, fragment)
end

local function is_ipv6(pkt)
   return rd16(pkt.data + o_ethernet_ethertype) == n_ethertype_ipv6
end

local function is_fragment(pkt)
   return pkt.data[ethernet_header_size + constants.o_ipv6_next_header] ==
      constants.ipv6_frag
end

function ReassembleV6:push ()
   local input, output = self.input.input, self.output.output
   local errors = self.output.errors

   for _=1,link.nreadable(input) do
      local pkt = receive(input)
      if is_ipv6(pkt) and is_fragment(pkt) then
         counter.add(self.counters["in-ipv6-frag-needs-reassembly"])
         local status, maybe_pkt, ejected = self:cache_fragment(pkt)
         if ejected then
            counter.add(self.counters["drop-ipv6-frag-random-evicted"])
         end

         if status == fragv6_h.REASSEMBLY_OK then
            counter.add(self.counters["in-ipv6-frag-reassembled"])
            transmit(output, maybe_pkt)
         elseif status == fragv6_h.FRAGMENT_MISSING then
            -- Nothing useful to be done yet, continue
         elseif status == fragv6_h.REASSEMBLY_INVALID then
            counter.add(self.counters["drop-ipv6-frag-invalid-reassembly"])
            if maybe_pkt then -- This is an ICMP packet
               transmit(errors, maybe_pkt)
            end
         else -- unreachable
            packet.free(pkt)
         end
      else
         -- Forward all packets that aren't IPv6 fragments.
         counter.add(self.counters["in-ipv6-frag-reassembly-unneeded"])
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
      if pkt.length > mtu + ehs and is_ipv6(pkt) then
         -- It's possible that the IPv6 packet has an IPv4 packet as
         -- payload, and that payload has the Don't Fragment flag set.
         -- However ignore this; the fragmentation policy of the L3
         -- protocol (in this case, IP) doesn't affect the L2 protocol.
         -- We always fragment.
         local unfragmentable_header_size = ehs + ipv6_fixed_header_size
         local pkts = fragmentv6.fragment(pkt, unfragmentable_header_size, mtu)
         for i=1,#pkts do
            counter.add(self.counters["out-ipv6-frag"])
            transmit(output, pkts[i])
         end
      else
         counter.add(self.counters["out-ipv6-frag-not"])
         transmit(output, pkt)
      end
   end
end

function NDP:new(conf)
   local o = setmetatable({}, {__index=NDP})
   o.conf = conf
   -- TODO: verify that the src and dst ipv6 addresses and src mac address
   -- have been provided, in pton format.
   if not conf.dst_eth then
      self.ns_pkt = ndp.form_ns(conf.src_eth, conf.src_ipv6, conf.dst_ipv6)
      self.ns_interval = 3 -- Send a new NS every three seconds.
      self.ns_max_retries = 5 -- Max number of NS retries.
      self.ns_retries = 0
   end
   o.dst_eth = conf.dst_eth -- Intentionally nil if to request by NS
   return o
end

function NDP:maybe_send_ns_request (output)
   if self.dst_eth then return end
   if self.ns_retries == self.ns_max_retries then
      error(("Could not resolve IPv6 address: %s"):format(
         ipv6:ntop(self.conf.dst_ipv6)))
   end
   self.next_ns_time = self.next_ns_time or engine.now()
   if self.next_ns_time <= engine.now() then
      self:send_ns(output)
      self.next_ns_time = engine.now() + self.ns_interval
      self.ns_retries = self.ns_retries + 1
   end
end

function NDP:send_ns (output)
   transmit(output, packet.clone(self.ns_pkt))
end

function NDP:push()
   local isouth, osouth = self.input.south, self.output.south
   local inorth, onorth = self.input.north, self.output.north

   -- TODO: do unsolicited neighbor advertisement on start and on
   -- configuration reloads?
   -- This would be an optimization, not a correctness issue
   self:maybe_send_ns_request(osouth)

   for _=1,link.nreadable(isouth) do
      local p = receive(isouth)
      if ndp.is_ndp(p) then
         if not self.dst_eth and ndp.is_solicited_neighbor_advertisement(p) then
            local dst_ethernet = ndp.get_dst_ethernet(p, {self.conf.dst_ipv6})
            if dst_ethernet then
               self.dst_eth = dst_ethernet
            end
            packet.free(p)
         elseif ndp.is_neighbor_solicitation_for_addr(p, self.conf.src_ipv6) then
            local snap = ndp.form_nsolicitation_reply(self.conf.src_eth, self.conf.src_ipv6, p)
            if snap then 
               transmit(osouth, snap)
            end
            packet.free(p)
         else -- TODO? incoming NDP that we don't handle; drop it silently
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
      addresses[ffi.string(conf.address, 16)] = true
   end
   if conf.addresses then
      for _, v in ipairs(conf.addresses) do
         addresses[ffi.string(v, 16)] = true
      end
   end
   return setmetatable({addresses = addresses}, {__index = ICMPEcho})
end

function ICMPEcho:push()
   local l_in, l_out, l_reply = self.input.south, self.output.north, self.output.south

   for _ = 1, link.nreadable(l_in) do
      local out, pkt = l_out, receive(l_in)

      if icmp.is_icmpv6_message(pkt, icmpv6_echo_request, 0) then
         local pkt_ipv6 = ipv6:new_from_mem(pkt.data + ethernet_header_size,
                                            pkt.length - ethernet_header_size)
         local pkt_ipv6_dst = ffi.string(pkt_ipv6:dst(), 16)
         if self.addresses[pkt_ipv6_dst] then
            ethernet:new_from_mem(pkt.data, ethernet_header_size):swap()

            -- Swap IP source/destination
            pkt_ipv6:dst(pkt_ipv6:src())
            pkt_ipv6:src(pkt_ipv6_dst)

            -- Change ICMP message type
            pkt.data[o_icmpv6_msg_type] = icmpv6_echo_reply

            -- Recalculate checksums
            wr16(pkt.data + o_icmpv6_checksum, 0)
            local ph_len = pkt.length - o_icmpv6_header
            local ph = pkt_ipv6:pseudo_header(ph_len, proto_icmpv6)
            local csum = checksum.ipsum(ffi.cast("uint8_t*", ph), ffi.sizeof(ph), 0)
            csum = checksum.ipsum(pkt.data + o_icmpv6_header, 4, bit.bnot(csum))
            csum = checksum.ipsum(pkt.data + o_icmpv6_header + 4,
                                  pkt.length - o_icmpv6_header - 4,
                                  bit.bnot(csum))
            wr16(pkt.data + o_icmpv6_checksum, htons(csum))

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
