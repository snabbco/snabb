-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- NDP address resolution (RFC 4861)

-- This app uses the neighbor discovery protocol to determine the
-- Ethernet address of an IPv6 next-hop.  It's a limited
-- implementation; if you need to route traffic to multiple IPv6
-- next-hops on the local network, probably you want to build a more
-- capable NDP app.
--
-- All non-NDP traffic coming in on the "south" interface (i.e., from
-- the network card) is directly forwarded out the "north" interface
-- to be handled by the network function.  Incoming traffic on the
-- "north" inferface is dropped until the MAC address of the next-hop
-- is known.  Once we do have a MAC address for the next-hop, this app
-- sends all outgoing traffic there, overwriting the source and
-- destination Ethernet addresses on outgoing southbound traffic.

module(..., package.seeall)

local bit      = require("bit")
local ffi      = require("ffi")
local packet   = require("core.packet")
local link     = require("core.link")
local lib      = require("core.lib")
local shm      = require("core.shm")
local checksum = require("lib.checksum")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv6     = require("lib.protocol.ipv6")
local alarms = require("lib.yang.alarms")
local counter = require("core.counter")
local S = require("syscall")

alarms.add_to_inventory(
   {alarm_type_id='ndp-resolution'},
   {resource=tostring(S.getpid()), has_clear=true,
    description='Raise up if NDP app cannot resolve IPv6 address'})
local resolve_alarm = alarms.declare_alarm(
   {resource=tostring(S.getpid()), alarm_type_id='ndp-resolution'},
   {perceived_severity = 'critical',
    alarm_text = 'Make sure you can NDP resolve IP addresses on NIC'})

local htons, ntohs = lib.htons, lib.ntohs
local htonl, ntohl = lib.htonl, lib.ntohl
local receive, transmit = link.receive, link.transmit

local mac_t = ffi.typeof('uint8_t[6]')
local ether_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint8_t  dhost[6];
   uint8_t  shost[6];
   uint16_t type;
} __attribute__((packed))
]]
local ipv6_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint32_t v_tc_fl; // version, tc, flow_label
   uint16_t payload_length;
   uint8_t  next_header;
   uint8_t  hop_limit;
   uint8_t  src_ip[16];
   uint8_t  dst_ip[16];
} __attribute__((packed))
]]
local icmpv6_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint8_t  type;
   uint8_t  code;
   uint16_t checksum;
} __attribute__((packed))
]]
local na_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint32_t flags;               /* Bit 31: Router; Bit 30: Solicited;
                                    Bit 29: Override; Bits 28-0: Reserved. */
   uint8_t  target_ip[16];
   uint8_t  options[0];
} __attribute__((packed))
]]
local ns_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint32_t flags;               /* Bits 31-0: Reserved.  */
   uint8_t  target_ip[16];
   uint8_t  options[0];
} __attribute__((packed))
]]
local option_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint8_t  type;
   uint8_t  length;
} __attribute__((packed))
]]
local ether_option_header_t = ffi.typeof ([[
/* All values in network byte order.  */
struct {
   $ header;
   uint8_t  addr[6];
} __attribute__((packed))
]], option_header_t)
local ipv6_pseudoheader_t = ffi.typeof [[
struct {
   char src_ip[16];
   char dst_ip[16];
   uint32_t ulp_length;
   uint32_t next_header;
} __attribute__((packed))
]]
local ndp_header_t = ffi.typeof([[
struct {
   $ ether;
   $ ipv6;
   $ icmpv6;
   uint8_t body[0];
} __attribute__((packed))]], ether_header_t, ipv6_header_t, icmpv6_header_t)

local function ptr_to(t) return ffi.typeof('$*', t) end
local ether_header_ptr_t = ptr_to(ether_header_t)
local ndp_header_ptr_t = ptr_to(ndp_header_t)
local na_header_ptr_t = ptr_to(na_header_t)
local ns_header_ptr_t = ptr_to(ns_header_t)
local option_header_ptr_t = ptr_to(option_header_t)
local ether_option_header_ptr_t = ptr_to(ether_option_header_t)

local ndp_header_len = ffi.sizeof(ndp_header_t)

local ether_type_ipv6 = 0x86DD
local proto_icmpv6 = 58
local icmpv6_ns = 135
local icmpv6_na = 136
local na_router_bit = 31
local na_solicited_bit = 30
local na_override_bit = 29
local option_source_link_layer_address = 1
local option_target_link_layer_address = 2

-- Special addresses
local ipv6_all_nodes_local_segment_addr = ipv6:pton("ff02::1")
local ipv6_unspecified_addr = ipv6:pton("0::0") -- aka ::/128
-- Really just the first 13 bytes of the following...
local ipv6_solicited_multicast = ipv6:pton("ff02:0000:0000:0000:0000:0001:ff00:00")

local scratch_ph = ipv6_pseudoheader_t()
local function checksum_pseudoheader_from_header(ipv6_fixed_header)
   scratch_ph.src_ip = ipv6_fixed_header.src_ip
   scratch_ph.dst_ip = ipv6_fixed_header.dst_ip
   scratch_ph.ulp_length = htonl(ntohs(ipv6_fixed_header.payload_length))
   scratch_ph.next_header = htonl(ipv6_fixed_header.next_header)
   return checksum.ipsum(ffi.cast('char*', scratch_ph),
                         ffi.sizeof(ipv6_pseudoheader_t), 0)
end

local function is_ndp(pkt)
   if pkt.length < ndp_header_len then return false end
   local h = ffi.cast(ndp_header_ptr_t, pkt.data)
   if ntohs(h.ether.type) ~= ether_type_ipv6 then return false end
   if h.ipv6.next_header ~= proto_icmpv6 then return false end
   return h.icmpv6.type >= 133 and h.icmpv6.type <= 137
end

local function make_ndp_packet(src_mac, dst_mac, src_ip, dst_ip, message_type,
                               message, option)
   local pkt = packet.allocate()

   pkt.length = ndp_header_len
   local h = ffi.cast(ndp_header_ptr_t, pkt.data)
   h.ether.dhost = dst_mac
   h.ether.shost = src_mac
   h.ether.type = htons(ether_type_ipv6)
   h.ipv6.v_tc_fl = 0
   lib.bitfield(32, h.ipv6, 'v_tc_fl', 0, 4, 6)  -- IPv6 Version
   lib.bitfield(32, h.ipv6, 'v_tc_fl', 4, 8, 0)  -- Traffic class
   lib.bitfield(32, h.ipv6, 'v_tc_fl', 12, 20, 0) -- Flow label
   h.ipv6.payload_length = 0
   h.ipv6.next_header = proto_icmpv6
   h.ipv6.hop_limit = 255
   h.ipv6.src_ip = src_ip
   h.ipv6.dst_ip = dst_ip
   h.icmpv6.type = message_type
   h.icmpv6.code = 0
   h.icmpv6.checksum = 0

   packet.append(pkt, message, ffi.sizeof(message))
   packet.append(pkt, option, ffi.sizeof(option))

   -- Now fix up lengths and checksums.
   h.ipv6.payload_length = htons(pkt.length - ffi.sizeof(ether_header_t)
   - ffi.sizeof(ipv6_header_t))
   ptr = ffi.cast('char*', h.icmpv6)
   local base_checksum = checksum_pseudoheader_from_header(h.ipv6)
   h.icmpv6.checksum = htons(checksum.ipsum(ptr,
                                            pkt.length - (ptr - pkt.data),
                                            bit.bnot(base_checksum)))
   return pkt
end

-- Respond to a neighbor solicitation for our own address.
local function make_na_packet(src_mac, dst_mac, src_ip, dst_ip, is_router)
   local message = na_header_t()
   local flags = bit.lshift(1, na_solicited_bit)
   if is_router then
      flags = bit.bor(bit.lshift(1, na_router_bit), flags)
   end
   message.flags = htonl(flags)
   message.target_ip = src_ip

   local option = ether_option_header_t()
   option.header.type = option_target_link_layer_address
   option.header.length = 1 -- One 8-byte unit.
   option.addr = src_mac

   return make_ndp_packet(src_mac, dst_mac, src_ip, dst_ip, icmpv6_na,
                          message, option)
end

-- Solicit a neighbor's address.
local function make_ns_packet(src_mac, src_ip, dst_mac, dst_ip, target_ip)
   local message = ns_header_t()
   message.flags = 0
   message.target_ip = target_ip

   local option = ether_option_header_t()
   option.header.type = option_source_link_layer_address
   option.header.length = 1 -- One 8-byte unit.
   option.addr = src_mac

   return make_ndp_packet(src_mac, dst_mac, src_ip, dst_ip, icmpv6_ns,
                          message, option)
end

local function verify_icmp_checksum(pkt)
   local h = ffi.cast(ndp_header_ptr_t, pkt.data)
   local ph_csum = checksum_pseudoheader_from_header(h.ipv6)
   local icmp_length = ntohs(h.ipv6.payload_length)
   local a = checksum.ipsum(ffi.cast('char*', h.icmpv6), icmp_length,
                            bit.bnot(ph_csum))
   return a == 0
end

local function ipv6_eq(a, b) return ffi.C.memcmp(a, b, 16) == 0 end

-- IPv6 multicast addresses start with FF.
local function is_address_multicast(ipv6_addr)
   return ipv6_addr[0] == 0xff
end

-- Solicited multicast addresses have their first 13 bytes set to
-- ff02::1:ff00:0/104, aka ff02:0000:0000:0000:0000:0001:ff[UV:WXYZ].
local function is_solicited_node_multicast_address(addr)
   return ffi.C.memcmp(addr, ipv6_solicited_multicast, 13) == 0
end

local function random_locally_administered_unicast_mac_address()
   local mac = lib.random_bytes(6)
   -- Bit 0 is 0, indicating unicast.  Bit 1 is 1, indicating locally
   -- administered.
   mac[0] = bit.lshift(mac[0], 2) + 2
   return mac
end

NDP = {}
NDP.shm = {
   ["next-hop-macaddr-v6"] = {counter},
   ["in-ndp-ns-bytes"]  = {counter},
   ["in-ndp-ns-packets"]  = {counter},
   ["out-ndp-ns-bytes"]  = {counter},
   ["out-ndp-ns-packets"]  = {counter},
   ["in-ndp-na-bytes"]  = {counter},
   ["in-ndp-na-packets"]  = {counter},
   ["out-ndp-na-bytes"]  = {counter},
   ["out-ndp-na-packets"]  = {counter},
}
local ndp_config_params = {
   -- Source MAC address will default to a random address.
   self_mac  = { default=false },
   -- Source IP is required though.
   self_ip   = { required=true },
   -- The next-hop MAC address can be statically configured.
   next_mac  = { default=false },
   -- But if the next-hop MAC isn't configured, NDP will figure it out.
   next_ip   = { default=false },
   is_router = { default=true },
   -- Emit alarms if set.
   alarm_notification = { default=false },
   -- This NDP resolver might be part of a set of peer processes sharing
   -- work via RSS.  In that case, a response will probably arrive only
   -- at one process, not all of them!  In that case we can arrange for
   -- the NDP app that receives the reply to write the resolved next-hop
   -- to a shared file.  RSS peers can poll that file.
   shared_next_mac_key = {},
}

function NDP:new(conf)
   local o = lib.parse(conf, ndp_config_params)
   if not o.self_mac then
      o.self_mac = random_locally_administered_unicast_mac_address()
   end
   if not o.next_mac then
      assert(o.next_ip, 'NDP needs next-hop IPv6 address to learn next-hop MAC')
      self.ns_interval = 3 -- Send a new NS every three seconds.
   end
   if o.next_ip then
      -- Construct Solicited-Node multicast address
      -- https://datatracker.ietf.org/doc/html/rfc4861#section-2.3
      o.solicited_node_mcast = ipv6:pton("ff02::1:ff00:0") -- /104
      o.solicited_node_mcast[13] = o.next_ip[13]
      o.solicited_node_mcast[14] = o.next_ip[14]
      o.solicited_node_mcast[15] = o.next_ip[15]
      -- Construct Ethernet multicast address
      -- https://datatracker.ietf.org/doc/html/rfc2464#section-7
      o.mac_mcast = ethernet:pton("33:33:00:00:00:00")
      o.mac_mcast[2] = o.solicited_node_mcast[12]
      o.mac_mcast[3] = o.solicited_node_mcast[13]
      o.mac_mcast[4] = o.solicited_node_mcast[14]
      o.mac_mcast[5] = o.solicited_node_mcast[15]
   end
   return setmetatable(o, {__index=NDP})
end

function NDP:ndp_resolving (ip)
   print(("NDP: Resolving '%s'"):format(ipv6:ntop(ip)))
   if self.alarm_notification then
      resolve_alarm:raise()
   end
end

function NDP:maybe_send_ns_request (output)
   if self.next_mac then return end
   self.next_ns_time = self.next_ns_time or engine.now()
   if self.next_ns_time <= engine.now() then
      self:ndp_resolving(self.next_ip)
      local ns = make_ns_packet(self.self_mac, self.self_ip,
                                self.mac_mcast, self.solicited_node_mcast,
                                self.next_ip)
      counter.add(self.shm["out-ndp-ns-bytes"], ns.length)
      counter.add(self.shm["out-ndp-ns-packets"])
      transmit(self.output.south, ns)
      self.next_ns_time = engine.now() + self.ns_interval
   end
end

function NDP:ndp_resolved (ip, mac, provenance)
   print(("NDP: '%s' resolved (%s)"):format(ipv6:ntop(ip), ethernet:ntop(mac)))
   if self.alarm_notification then
      resolve_alarm:clear()
   end
   self.next_mac = mac
   if self.next_mac then
      local buf = ffi.new('union { uint64_t u64; uint8_t bytes[6]; }')
      buf.bytes = self.next_mac
      counter.set(self.shm["next-hop-macaddr-v6"], buf.u64)
   end
   if self.shared_next_mac_key then
      if provenance == 'remote' then
         -- If we are getting this information from a packet and not
         -- from the shared key, then update the shared key.
         local ok, shared = pcall(shm.create, self.shared_next_mac_key, mac_t)
         if not ok then
            ok, shared = pcall(shm.open, self.shared_next_mac_key, mac_t)
         end
         if not ok then
            print('warning: ndp: failed to update shared next MAC key!')
         else
            ffi.copy(shared, mac, 6)
            shm.unmap(shared)
         end
      else
         assert(provenance == 'peer')
         -- Pass.
      end
   end
end

function NDP:resolve_next_hop(next_mac)
   -- It's possible for a NA packet to indicate the MAC address in
   -- more than one way (e.g. unicast ethernet source address and the
   -- link layer address in the NDP options).  Just take the first
   -- one.
   if self.next_mac then return end
   self:ndp_resolved(self.next_ip, next_mac, 'remote')
end

local function copy_mac(src)
   local dst = ffi.new('uint8_t[6]')
   ffi.copy(dst, src, 6)
   return dst
end

function NDP:handle_ndp (pkt)
   local h = ffi.cast(ndp_header_ptr_t, pkt.data)
   -- Generic checks.
   if h.ipv6.hop_limit ~= 255 then return end
   if h.icmpv6.code ~= 0 then return end
   if not verify_icmp_checksum(pkt) then return end

   if h.icmpv6.type == icmpv6_na then
      counter.add(self.shm["in-ndp-na-bytes"], pkt.length)
      counter.add(self.shm["in-ndp-na-packets"])
      -- Only process advertisements when we are looking for a
      -- next-hop MAC.
      if self.next_mac then return end
      -- Drop packets that are too short.
      if pkt.length < ndp_header_len + ffi.sizeof(na_header_t) then return end
      local na = ffi.cast(na_header_ptr_t, h.body)
      local solicited = bit.lshift(1, na_solicited_bit)
      -- Reject unsolicited advertisements.
      if bit.band(solicited, ntohl(na.flags)) ~= solicited then return end
      -- We only are looking for the MAC of our next-hop; no others.
      if not ipv6_eq(na.target_ip, self.next_ip) then return end
      -- First try to get the MAC from the options.
      local offset = na.options - pkt.data
      while offset < pkt.length do
         local option = ffi.cast(option_header_ptr_t, pkt.data + offset)
         -- Any option whose length is 0 or too large causes us to
         -- drop the packet.
         if option.length == 0 then return end
         if offset + option.length*8 > pkt.length then return end
         offset = offset + option.length*8
         if option.type == option_target_link_layer_address then
            if option.length ~= 1 then return end
            local ether = ffi.cast(ether_option_header_ptr_t, option)
            self:resolve_next_hop(copy_mac(ether.addr))
         end
      end
      -- Otherwise, when responding to unicast solicitations, the
      -- option can be omitted since the sender of the solicitation
      -- has the correct link-layer address.  See 4.4. Neighbor
      -- Advertisement Message Format.
      self:resolve_next_hop(copy_mac(h.ether.shost))
   elseif h.icmpv6.type == icmpv6_ns then
      counter.add(self.shm["in-ndp-ns-bytes"], pkt.length)
      counter.add(self.shm["in-ndp-ns-packets"])
      if pkt.length < ndp_header_len + ffi.sizeof(ns_header_t) then return end
      local ns = ffi.cast(ns_header_ptr_t, h.body)
      if is_address_multicast(ns.target_ip) then return end
      if not ipv6_eq(ns.target_ip, self.self_ip) then return end
      local dst_ip
      if ipv6_eq(h.ipv6.src_ip, ipv6_unspecified_addr) then
         if is_solicited_node_multicast_address(h.ipv6.dst_ip) then return end
         dst_ip = ipv6_all_nodes_local_segment_addr
      else
         dst_ip = h.ipv6.src_ip
      end
      -- We don't need the options, but we do need to check them for
      -- validity.
      local offset = ns.options - pkt.data
      while offset < pkt.length do
         local option = ffi.cast(option_header_ptr_t, pkt.data + offset)
         -- Any option whose length is 0 or too large causes us to
         -- drop the packet.
         if option.length == 0 then return end
         if offset + option.length * 8 > pkt.length then return end
         offset = offset + option.length*8
         if option.type == option_source_link_layer_address then
            if ipv6_eq(h.ipv6.src_ip, ipv6_unspecified_addr) then
               return
            end
         end
      end
      local na = make_na_packet(self.self_mac, h.ether.shost,
                                self.self_ip, dst_ip, self.is_router)
      counter.add(self.shm["out-ndp-na-bytes"], na.length)
      counter.add(self.shm["out-ndp-na-packets"])
      link.transmit(self.output.south, na)
   else
      -- Unhandled NDP packet; silently drop.
      return
   end
end

function NDP:push()
   local isouth, osouth = self.input.south, self.output.south
   local inorth, onorth = self.input.north, self.output.north

   -- TODO: do unsolicited neighbor advertisement on start and on
   -- configuration reloads?
   -- This would be an optimization, not a correctness issue
   self:maybe_send_ns_request(osouth)

   for _ = 1, link.nreadable(isouth) do
      local p = receive(isouth)
      if is_ndp(p) then
         self:handle_ndp(p)
         packet.free(p)
      else
         transmit(onorth, p)
      end
   end

   -- Don't read southbound packets until the next hop's ethernet
   -- address is known.
   if self.next_mac then
      for _ = 1, link.nreadable(inorth) do
         local p = receive(inorth)
         local h = ffi.cast(ether_header_ptr_t, p.data)
         h.shost = self.self_mac
         h.dhost = self.next_mac
         transmit(osouth, p)
      end
   elseif self.shared_next_mac_key then
      local ok, mac = pcall(shm.open, self.shared_next_mac_key, mac_t)
      -- Use the shared pointer directly, without copying; if it is ever
      -- updated, we will get its new value.
      if ok then self:ndp_resolved(self.next_ip, mac, 'peer') end
   end
end

function selftest()
   print("selftest: ndp")

   local config = require("core.config")
   local sink = require("apps.basic.basic_apps").Sink
   local c = config.new()
   config.app(c, "nd1", NDP, { self_ip  = ipv6:pton("2001:DB8::1"),
                               next_ip  = ipv6:pton("2001:DB8::2"),
                               shared_next_mac_key = "foo" })
   config.app(c, "nd2", NDP, { self_ip  = ipv6:pton("2001:DB8::2"),
                               next_ip  = ipv6:pton("2001:DB8::1"),
                               shared_next_mac_key = "bar" })
   config.app(c, "sink1", sink)
   config.app(c, "sink2", sink)
   config.link(c, "nd1.south -> nd2.south")
   config.link(c, "nd2.south -> nd1.south")
   config.link(c, "sink1.tx -> nd1.north")
   config.link(c, "nd1.north -> sink1.rx")
   config.link(c, "sink2.tx -> nd2.north")
   config.link(c, "nd2.north -> sink2.rx")
   engine.configure(c)
   local breaths = counter.read(engine.breaths)
   local function done() return counter.read(engine.breaths)-breaths > 1 end
   engine.main({ done = done })

   local function mac_eq(a, b) return ffi.C.memcmp(a, b, 6) == 0 end
   local nd1, nd2 = engine.app_table.nd1, engine.app_table.nd2
   assert(nd1.next_mac)
   assert(nd2.next_mac)
   assert(mac_eq(nd1.next_mac, nd2.self_mac))
   assert(mac_eq(nd2.next_mac, nd1.self_mac))

   print("selftest: ok")
end
