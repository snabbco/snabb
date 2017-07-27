module(..., package.seeall)

local constants = require("apps.lwaftr.constants")
local fragmentv6 = require("apps.lwaftr.fragmentv6")
local fragv6_h = require("apps.lwaftr.fragmentv6_hardened")
local lwutil = require("apps.lwaftr.lwutil")
local icmp = require("apps.lwaftr.icmp")
local lwcounter = require("apps.lwaftr.lwcounter")

local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local checksum = require("lib.checksum")
local packet = require("core.packet")
local counter = require("core.counter")
local lib = require("core.lib")
local link = require("core.link")
local engine = require("core.app")

local bit = require("bit")
local ffi = require("ffi")

local receive, transmit = link.receive, link.transmit
local wr16 = lwutil.wr16
local is_ipv6, is_ipv6_fragment = lwutil.is_ipv6, lwutil.is_ipv6_fragment
local htons = lib.htons

local ipv6_fixed_header_size = constants.ipv6_fixed_header_size

local proto_icmpv6 = constants.proto_icmpv6
local ethernet_header_size = constants.ethernet_header_size
local o_icmpv6_header = ethernet_header_size + ipv6_fixed_header_size
local o_icmpv6_msg_type = o_icmpv6_header + constants.o_icmpv6_msg_type
local o_icmpv6_checksum = o_icmpv6_header + constants.o_icmpv6_checksum
local icmpv6_echo_request = constants.icmpv6_echo_request
local icmpv6_echo_reply = constants.icmpv6_echo_reply
local ehs = constants.ethernet_header_size

ReassembleV6 = {}
Fragmenter = {}
ICMPEcho = {}

function ReassembleV6:new(conf)
   local max_ipv6_reassembly_packets = conf.max_ipv6_reassembly_packets
   local max_fragments_per_reassembly_packet = conf.max_fragments_per_reassembly_packet
   local o = {
      counters = lwcounter.init_counters(),
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

function ReassembleV6:push ()
   local input, output = self.input.input, self.output.output
   local errors = self.output.errors

   for _ = 1, link.nreadable(input) do
      local pkt = receive(input)
      if is_ipv6_fragment(pkt) then
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
      counters = lwcounter.init_counters(),
      mtu = assert(conf.mtu),
   }
   return setmetatable(o, {__index=Fragmenter})
end

function Fragmenter:push ()
   local input, output = self.input.input, self.output.output

   local mtu = self.mtu

   for _ = 1, link.nreadable(input) do
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
