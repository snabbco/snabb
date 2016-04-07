module(..., package.seeall)

local constants = require("apps.lwaftr.constants")
local fragmentv6 = require("apps.lwaftr.fragmentv6")
local ndp = require("apps.lwaftr.ndp")
local lwutil = require("apps.lwaftr.lwutil")
local icmp = require("apps.lwaftr.icmp")

local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local checksum = require("lib.checksum")
local packet = require("core.packet")
local bit = require("bit")
local ffi = require("ffi")
local C = ffi.C

local receive, transmit = link.receive, link.transmit
local rd16, wr16, htons = lwutil.rd16, lwutil.wr16, lwutil.htons
local is_fragment = fragmentv6.is_fragment

local ipv6_fixed_header_size = constants.ipv6_fixed_header_size
local n_ethertype_ipv6 = constants.n_ethertype_ipv6
local o_ipv6_src_addr = constants.o_ipv6_src_addr
local o_ipv6_dst_addr = constants.o_ipv6_dst_addr

local proto_icmpv6 = constants.proto_icmpv6
local ethernet_header_size = constants.ethernet_header_size
local o_icmpv6_header = ethernet_header_size + ipv6_fixed_header_size
local o_icmpv6_msg_type = o_icmpv6_header + constants.o_icmpv6_msg_type
local o_icmpv6_checksum = o_icmpv6_header + constants.o_icmpv6_checksum
local icmpv6_echo_request = constants.icmpv6_echo_request
local icmpv6_echo_reply = constants.icmpv6_echo_reply

Reassembler = {}
Fragmenter = {}
NDP = {}
ICMPEcho = {}

function Reassembler:new(conf)
   local o = setmetatable({}, {__index=Reassembler})
   o.conf = conf

   if conf.vlan_tagging then
      o.l2_size = constants.ethernet_header_size + 4
      o.ethertype_offset = constants.o_ethernet_ethertype + 4
   else
      o.l2_size = constants.ethernet_header_size
      o.ethertype_offset = constants.o_ethernet_ethertype
   end
   o.fragment_cache = {}
   return o
end

local function get_ipv6_src_ip(pkt, l2_size)
   local ipv6_src = l2_size + o_ipv6_src_addr
   return ffi.string(pkt.data + ipv6_src, 16)
end

local function get_ipv6_dst_ip(pkt, l2_size)
   local ipv6_dst = l2_size + o_ipv6_dst_addr
   return ffi.string(pkt.data + ipv6_dst, 16)
end

function Reassembler:key_frag(frag)
   local l2_size = self.l2_size
   local frag_id = fragmentv6.get_frag_id(frag, l2_size)
   local src_ip = get_ipv6_src_ip(frag, l2_size)
   local dst_ip = get_ipv6_dst_ip(frag, l2_size)
   return frag_id .. '|' .. src_ip .. dst_ip
end

function Reassembler:cache_fragment(frag)
   local cache = self.fragment_cache
   local key = self:key_frag(frag)
   cache[key] = cache[key] or {}
   table.insert(cache[key], frag)
   return cache[key]
end

function Reassembler:clean_fragment_cache(frags)
   local key = self:key_frag(frags[1])
   self.fragment_cache[key] = nil
   for _, p in ipairs(frags) do
      packet.free(p)
   end
end

local function is_ipv6(pkt, ethertype_offset)
   return rd16(pkt.data + ethertype_offset) == n_ethertype_ipv6
end

function Reassembler:push ()
   local input, output = self.input.input, self.output.output
   local errors = self.output.errors

   local l2_size = self.l2_size
   local ethertype_offset = self.ethertype_offset

   for _=1,link.nreadable(input) do
      local pkt = receive(input)
      if is_ipv6(pkt, ethertype_offset) and is_fragment(pkt, l2_size) then
         local frags = self:cache_fragment(pkt)
         local status, maybe_pkt = fragmentv6.reassemble(frags, l2_size)
         if status == fragmentv6.REASSEMBLY_OK then
            self:clean_fragment_cache(frags)
            transmit(output, maybe_pkt)
         elseif status == fragmentv6.FRAGMENT_MISSING then
            -- Nothing useful to be done yet
         elseif status == fragmentv6.REASSEMBLY_INVALID then
            self:clean_fragment_cache(frags)
            if maybe_pkt then -- This is an ICMP packet
               transmit(errors, maybe_pkt)
            end
         else -- unreachable
            packet.free(pkt)
         end
      else
         -- Forward all packets that aren't IPv6 fragments.
         transmit(output, pkt)
      end
   end
end

function Fragmenter:new(conf)
   local o = setmetatable({}, {__index=Fragmenter})
   o.conf = conf

   o.mtu = assert(conf.mtu)

   if conf.vlan_tagging then
      o.l2_size = constants.ethernet_header_size + 4
      o.ethertype_offset = constants.o_ethernet_ethertype + 4
   else
      o.l2_size = constants.ethernet_header_size
      o.ethertype_offset = constants.o_ethernet_ethertype
   end

   return o
end

function Fragmenter:push ()
   local input, output = self.input.input, self.output.output
   local errors = self.output.errors

   local l2_size, mtu = self.l2_size, self.mtu
   local ethertype_offset = self.ethertype_offset

   for _=1,link.nreadable(input) do
      local pkt = receive(input)
      if pkt.length > mtu + l2_size and is_ipv6(pkt, ethertype_offset) then
         -- It's possible that the IPv6 packet has an IPv4 packet as
         -- payload, and that payload has the Don't Fragment flag set.
         -- However ignore this; the fragmentation policy of the L3
         -- protocol (in this case, IP) doesn't affect the L2 protocol.
         -- We always fragment.
         local unfragmentable_header_size = l2_size + ipv6_fixed_header_size
         local pkts = fragmentv6.fragment(pkt, unfragmentable_header_size,
                                          l2_size, mtu)
         for i=1,#pkts do
            transmit(output, pkts[i])
         end
      else
         transmit(output, pkt)
      end
   end
end

-- TODO: handle any NS retry policy code here
function NDP:new(conf)
   local o = setmetatable({}, {__index=NDP})
   o.conf = conf
   -- TODO: verify that the src and dst ipv6 addresses and src mac address
   -- have been provided, in pton format.
   if not conf.dst_eth then
      o.ns_pkt = ndp.form_ns(conf.src_eth, conf.src_ipv6, conf.dst_ipv6)
      o.do_ns_request = true
   else
       o.do_ns_request = false
   end
   o.dst_eth = conf.dst_eth -- Intentionally nil if to request by NS
   o.all_local_ipv6_ips = conf.all_ipv6_addrs
   return o
end

function NDP:push()
   local isouth, osouth = self.input.south, self.output.south
   local inorth, onorth = self.input.north, self.output.north
   if self.do_ns_request then
      self.do_ns_request = false -- TODO: have retries, etc
      transmit(osouth, packet.clone(self.ns_pkt))
      -- TODO: do unsolicited neighbor advertisement on start and on
      -- configuration reloads?
      -- This would be an optimization, not a correctness issue
   end
   for _=1,link.nreadable(isouth) do
      local p = receive(isouth)
      if ndp.is_ndp(p) then
         if not self.dst_eth and ndp.is_solicited_neighbor_advertisement(p) then
            local dst_ethernet = ndp.get_dst_ethernet(p, {self.conf.dst_ipv6})
            if dst_ethernet then
               self.dst_eth = dst_ethernet
            end
            packet.free(p)
         elseif ndp.is_neighbor_solicitation_for_ips(p, self.all_local_ipv6_ips) then
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

   for _ = 1, math.min(link.nreadable(l_in), link.nwritable(l_out)) do
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
   for _ = 1, math.min(link.nreadable(l_in), link.nwritable(l_out)) do
      transmit(l_out, receive(l_in))
   end
end
