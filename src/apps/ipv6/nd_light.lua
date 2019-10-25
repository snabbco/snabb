-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- This app implements a small subset of IPv6 neighbor discovery
-- (RFC4861).  It has two ports, north and south.  The south port
-- attaches to a port on which ND must be performed.  The north port
-- attaches to an app that processes IPv6 packets.  Packets
-- transmitted to and received from the north port contain full
-- Ethernet frames.
--
-- The app replies to neighbor solicitations for which it is
-- configured as target and performs rudimentary address resolution
-- for its configured "next-hop" address.  This is done by
-- transmitting a neighbor solicitation for the hext-hop with a
-- configurable number of retransmits (default 10) with a configurable
-- interval (default 1000ms) and processing the (solicited) neighbor
-- advertisements.
--
-- If address resolution succeeds, the app constructs an Ethernet
-- header with the discovered destination address, configured source
-- address and ethertype 0x86dd and overwrites the headers of all
-- packets received from the north port with it.  The resulting
-- packets are transmitted to the south port.  All packets from the
-- north port are discarded as long as ND has not yet succeeded.
--
-- Address resolution is not repeated for the lifetime of the app.
-- The app terminates if address resolution has not succeeded after
-- all retransmits have been performed.
--
-- Packets received from the south port are transmitted to the north
-- port unaltered, i.e. including the Ethernet header.

module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local app = require("core.app")
local link = require("core.link")
local config = require("core.config")
local packet = require("core.packet")
local counter = require("core.counter")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local icmp = require("lib.protocol.icmp.header")
local ns = require("lib.protocol.icmp.nd.ns")
local na = require("lib.protocol.icmp.nd.na")
local tlv = require("lib.protocol.icmp.nd.options.tlv")
local filter = require("lib.pcap.filter")
local timer = require("core.timer")
local lib = require("core.lib")
local logger = require("lib.logger")

nd_light = subClass(nil)
nd_light._name = "Partial IPv6 neighbor discovery"
nd_light.config = {
   local_mac = {required=true},
   remote_mac = {},
   local_ip = {required=true},
   next_hop =  {required=true},
   delay = {default=1000},
   retrans = {},
   quiet = {default=false}
}
nd_light.shm = {
   status                   = {counter, 2}, -- Link down
   rxerrors                 = {counter},
   txerrors                 = {counter},
   txdrop                   = {counter},
   ns_checksum_errors       = {counter},
   ns_target_address_errors = {counter},
   na_duplicate_errors      = {counter},
   na_target_address_errors = {counter},
   nd_protocol_errors       = {counter}
}

-- config:
--   local_mac  MAC address of the interface attached to "south".
--              Accepted formats:
--                6-byte on-the-wire representaion, either as a cdata
--                object (e.g. as returned by lib.protocol.ethernet:pton())
--                or a Lua string of lengh 6.
--
--                String with regular colon-notation.
--   local_ip   IPv6 address of the interface. Accepted formats:
--                16-byte on-the-wire representation, either as a cdata
--                object (e.g as returned by lib.protocol.ipv6:pton()) or
--                a Lus string of length 16.
--   next_hop   IPv6 address of next-hop for all packets to south.  Accepted
--              formats as for local_ip.
--   remote_mac Optional MAC address of next_hop in case dynamic ND is not
--              available on the link
--   delay      NS retransmit delay in ms (default 1000ms)
--   retrans    Number of NS retransmits (default 10)
local function check_ip_address (ip, desc)
   if type(ip) == "string" and string.len(ip) ~= 16 then
      ip = ipv6:pton(ip)
   else
      assert(type(ip) == "cdata",
             "nd_light: invalid type of "..desc.." IP address, expected cdata, got "
                ..type(ip))
   end
   return ip
end

local function check_mac_address (mac, desc)
   if type(mac) == "string" and string.len(mac) ~= 6 then
      mac = ethernet:pton(mac)
   else
      assert(type(mac) == "cdata",
             "nd_light: invalid type of "..desc.." MAC address, expected cdata, got "
                ..type(mac))
   end
   return mac
end

function _new (self, conf)
   conf.local_ip = check_ip_address(conf.local_ip, "local")
   conf.next_hop = check_ip_address(conf.next_hop, "next-hop")
   conf.local_mac = check_mac_address(conf.local_mac, "local")
   if conf.remote_mac then
      conf.remote_mac = check_mac_address(conf.remote_mac, "remote")
      self._eth_header = ethernet:new({ src = conf.local_mac,
                                        dst = conf.remote_mac,
                                        type = 0x86dd })
   end

   self._config = conf
   self._match_ns = function(ns)
                    return(ns:target_eq(conf.local_ip))
                 end
   self._match_na = function(na)
                    return(na:target_eq(conf.next_hop) and na:solicited() == 1)
                 end

   -- Prepare packet for solicitation of next hop
   local nh = self._next_hop
   local dgram = datagram:new()
   local sol_node_mcast = ipv6:solicited_node_mcast(conf.next_hop)
   local ipv6 = ipv6:new({ next_header = 58, -- ICMP6
         hop_limit = 255,
         src = conf.local_ip,
         dst = sol_node_mcast })
   local icmp = icmp:new(135, 0)

   -- Construct a neighbor solicitation with a source link-layer
   -- option.
   local ns = ns:new(conf.next_hop)
   local src_lladdr_tlv = tlv:new(1, conf.local_mac):tlv()
   local src_lladdr_tlv_len = ffi.sizeof(src_lladdr_tlv)
   -- We add both chunks to the payload rather than using push() for
   -- the ns header to have everything in a contiguous block for
   -- checksum calculation.
   dgram:payload(ns:header(), ns:sizeof())
   local mem, length = dgram:payload(src_lladdr_tlv, src_lladdr_tlv_len)
   icmp:checksum(mem, length, ipv6)
   dgram:push(icmp)
   ipv6:payload_length(icmp:sizeof() + ns:sizeof() + src_lladdr_tlv_len)
   dgram:push(ipv6)
   dgram:push(ethernet:new({ src = conf.local_mac,
                             dst = ethernet:ipv6_mcast(sol_node_mcast),
                             type = 0x86dd }))
   nh.packet = dgram:packet()
   dgram:free()

   -- Prepare packet for solicited neighbor advertisement
   local sna = self._sna
   dgram = datagram:new()
   -- Leave dst address unspecified.  It will be set to the source of
   -- the incoming solicitation
   ipv6 = ipv6:new({ next_header = 58, -- ICMP6
                     hop_limit = 255,
                     src = conf.local_ip })
   icmp = icmp:new(136, 0)
   -- Construct a neighbor solicitation with a target link-layer
   -- option.
   local na = na:new(conf.local_ip, nil, 1, nil)
   local tgt_lladdr_tlv = tlv:new(2, conf.local_mac):tlv()
   local tgt_lladdr_tlv_len = ffi.sizeof(tgt_lladdr_tlv)
   dgram:payload(na:header(), na:sizeof())
   local mem, length = dgram:payload(tgt_lladdr_tlv, tgt_lladdr_tlv_len)
   icmp:checksum(mem, length, ipv6)
   dgram:push(icmp)
   ipv6:payload_length(icmp:sizeof() + na:sizeof() + tgt_lladdr_tlv_len)
   dgram:push(ipv6)
   -- Leave dst address unspecified.
   dgram:push(ethernet:new({ src = conf.local_mac,
                             type = 0x86dd }))
   sna.packet = dgram:packet()

   -- Parse the headers we want to modify later on from our template
   -- packet.
   dgram = dgram:new(sna.packet, ethernet)
   dgram:parse_n(3)
   sna.eth, sna.ipv6, sna.icmp = unpack(dgram:stack())
   sna.dgram = dgram
   return self
end

function nd_light:new (arg)
   local o = nd_light:superClass().new(self)
   local nh = { nsent = 0 }
   o._next_hop = nh
   o._sna = {}
   local errmsg
   o._filter, errmsg = filter:new("icmp6 and ( ip6[40] = 135 or ip6[40] = 136 )")
   assert(o._filter, errmsg and ffi.string(errmsg))

   _new(o, arg)

   -- Timer for retransmits of neighbor solicitations
   nh.timer_cb = function (t)
      local nh = o._next_hop
      -- If nh.packet is nil the app was stopped and we
      -- bail out.
      if not nh.packet then return nil end
      if not o._config.quiet then
         o._logger:log(string.format("Sending neighbor solicitation for next-hop %s",
                                     ipv6:ntop(o._config.next_hop)))
      end
      link.transmit(o.output.south, packet.clone(nh.packet))
      nh.nsent = nh.nsent + 1
      if (not o._config.retrans or nh.nsent <= o._config.retrans)
         and not o._eth_header
      then
         timer.activate(nh.timer)
      end
      if o._config.retrans and nh.nsent > o._config.retrans then
         error(string.format("ND for next hop %s has failed",
                             ipv6:ntop(o._config.next_hop)))
      end
   end
   nh.timer = timer.new("ns retransmit",
                        nh.timer_cb, 1e6 * o._config.delay)

   -- Caches for for various cdata pointer objects to avoid boxing in
   -- the push() loop
   o._cache = {
      p = ffi.new("struct packet *[1]"),
      mem = ffi.new("uint8_t *[1]")
   }
   o._logger = logger.new({ module = 'nd_light' })

   return o
end

function nd_light:reconfig (arg)
   -- Free static packets
   self:stop()
   return _new(self, arg)
end

-- Process neighbor solicitation
local function ns (self, dgram, eth, ipv6, icmp)
   local mem, length = self._cache.mem
   mem[0], length = dgram:payload()
   if not icmp:checksum_check(mem[0], length, ipv6) then
      counter.add(self.shm.ns_checksum_errors)
      counter.add(self.shm.rxerrors)
      return nil
   end
   -- Parse the neighbor solicitation and check if it contains our own
   -- address as target
   local ns = dgram:parse_match(nil, self._match_ns)
   if not ns then
      counter.add(self.shm.ns_target_address_errors)
      counter.add(self.shm.rxerrors)
      return nil
   end
   -- Ignore options as long as we don't implement a proper neighbor
   -- cache.

   -- Set Ethernet and IPv6 destination addresses and re-compute the
   -- ICMP checksum
   local sna = self._sna
   sna.eth:dst(eth:src())
   sna.ipv6:dst(ipv6:src())
   -- The payload of the pre-fabricated packet consists of the NA and
   -- target ll-option
   mem[0], length = sna.dgram:payload()
   sna.icmp:checksum(mem[0], length, sna.ipv6)
   return true
end

-- Process neighbor advertisement
local function na (self, dgram, eth, ipv6, icmp)
   if self._eth_header then
      counter.add(self.shm.na_duplicate_errors)
      counter.add(self.shm.rxerrors)
      return nil
   end
   local na = dgram:parse_match(nil, self._match_na)
   if not na then
      counter.add(self.shm.na_target_address_errors)
      counter.add(self.shm.rxerrors)
      return nil
   end
   local option = na:options(dgram:payload())
   if not (#option == 1 and option[1]:type() == 2) then
      -- Invalid NS, ignore
      counter.add(self.shm.nd_protocol_errors)
      counter.add(self.shm.rxerrors)
      return nil
   end
   self._eth_header = ethernet:new({ src = self._config.local_mac,
                                     dst = option[1]:option():addr(),
                                     type = 0x86dd })
   self._logger:log(string.format("Resolved next-hop %s to %s",
                                  ipv6:ntop(self._config.next_hop),
                                  ethernet:ntop(option[1]:option():addr())))
   counter.set(self.shm.status, 1) -- Link up
   return nil
end

local function from_south (self, p)
   if not self._filter:match(p[0].data, p[0].length) then
      return false
   end
   local dgram = datagram:new(p[0], ethernet)
   -- Parse the ethernet, ipv6 amd icmp headers
   dgram:parse_n(3)
   local eth, ipv6, icmp = unpack(dgram:stack())
   if ipv6:hop_limit() ~= 255 then
      -- Avoid off-link spoofing as per RFC
      counter.add(self.shm.nd_protocol_errors)
      counter.add(self.shm.rxerrors)
      return nil
   end
   local result
   if icmp:type() == 135 then
      result = ns(self, dgram, eth, ipv6, icmp)
   else
      result = na(self, dgram, eth, ipv6, icmp)
   end
   dgram:free()
   return result
end

function nd_light:push ()
   if self._next_hop.nsent == 0 and self._eth_header == nil then
      -- Kick off address resolution
      self._next_hop.timer_cb()
   end

   local cache = self._cache
   local l_in = self.input.south
   local l_out = self.output.north
   local l_reply = self.output.south
   while not link.empty(l_in) do
      local p = cache.p
      p[0] = link.receive(l_in)
      local status = from_south(self, p)
      if status == nil then
         -- Discard
         packet.free(p[0])
      elseif status == true then
         -- Send NA back south
         packet.free(p[0])
         link.transmit(l_reply, packet.clone(self._sna.packet))
      else
         -- Send transit traffic up north
         link.transmit(l_out, p[0])
      end
   end

   l_in = self.input.north
   l_out = self.output.south
   while not link.empty(l_in) do
      if not self._eth_header then
         -- Drop packets until ND for the next-hop
         -- has completed.
         packet.free(link.receive(l_in))
         counter.add(self.shm.txdrop)
      else
         local p = cache.p
         p[0] = link.receive(l_in)
         if p[0].length >= self._eth_header:sizeof() then
            self._eth_header:copy(p[0].data)
            link.transmit(l_out, p[0])
         else
            packet.free(p[0])
            counter.add(self.shm.txerrors)
         end
      end
   end
end

-- Free static packets on `stop'.
function nd_light:stop ()
   packet.free(self._next_hop.packet)
   self._next_hop.packet = nil
   packet.free(self._sna.packet)
   self._sna.packet = nil
end

function selftest ()
   local sink = require("apps.basic.basic_apps").Sink
   local c = config.new()
   config.app(c, "nd1", nd_light, { local_mac = "00:00:00:00:00:01",
                                    local_ip  = "2001:DB8::1",
                                    next_hop  = "2001:DB8::2" })
   config.app(c, "nd2", nd_light, { local_mac = "00:00:00:00:00:02",
                                    local_ip  = "2001:DB8::2",
                                    next_hop  = "2001:DB8::1" })
   config.app(c, "sink1", sink)
   config.app(c, "sink2", sink)
   config.link(c, "nd1.south -> nd2.south")
   config.link(c, "nd2.south -> nd1.south")
   config.link(c, "sink1.tx -> nd1.north")
   config.link(c, "nd1.north -> sink1.rx")
   config.link(c, "sink2.tx -> nd2.north")
   config.link(c, "nd2.north -> sink2.rx")
   engine.configure(c)
   engine.main({ duration = 2 })
   assert(engine.app_table.nd1._eth_header)
   assert(engine.app_table.nd2._eth_header)
end
