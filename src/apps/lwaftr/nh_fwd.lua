module(..., package.seeall)

local app = require("core.app")
local basic_apps = require("apps.basic.basic_apps")
local constants = require("apps.lwaftr.constants")
local ethernet = require("lib.protocol.ethernet")
local tcp = require("lib.protocol.tcp")
local udp = require("lib.protocol.udp")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local lib = require("core.lib")
local lwutil = require("apps.lwaftr.lwutil")
local shm = require("core.shm")

local ffi = require("ffi")
local C = ffi.C

local transmit, receive = link.transmit, link.receive
local rd16, rd32 = lwutil.rd16, lwutil.rd32
local ipv6_equals = lwutil.ipv6_equals

nh_fwd4 = {
   config = {
      mac_address = {required=true},
      service_mac = {required=false, default=nil},
      ipv4_address = {required=true},
      debug = {default=false},
      cache_refresh_interval = {default=0},
      next_hop_mac = {required=false, default=nil}
   }
}
nh_fwd6 = {
   config = {
      mac_address = {required=true},
      service_mac = {required=false, default=nil},
      debug = {default=false},
      cache_refresh_interval = {default=0},
      next_hop_mac = {required=false, default=nil}
   }
}

local proto_tcp = constants.proto_tcp
local proto_udp = constants.proto_udp

local ethernet_header_size = constants.ethernet_header_size
local n_ethertype_ipv4 = constants.n_ethertype_ipv4
local proto_ipv4 = constants.proto_ipv4
local ipv6_frag = constants.ipv6_frag
local o_ipv4_dst_addr = constants.o_ipv4_dst_addr
local o_ipv4_src_addr = constants.o_ipv4_src_addr
local o_ipv6_next_header = constants.o_ipv6_next_header
local o_ipv6_src_addr = constants.o_ipv6_src_addr
local ipv6_fixed_header_size = constants.ipv6_fixed_header_size

local n_cache_src_ipv4 = ipv4:pton("169.254.254.254")
local val_cache_src_ipv4 = rd32(n_cache_src_ipv4)
local n_cache_src_ipv6 = ipv6:pton("fe80::")
local n_next_hop_mac_empty = ethernet:pton("00:00:00:00:00:00")

local function get_ethertype(pkt)
   return rd16(pkt.data + (ethernet_header_size - 2))
end
local function get_ethernet_payload(pkt)
   return pkt.data + ethernet_header_size
end
local function get_ipv4_dst_address(ptr)
   return rd32(ptr + o_ipv4_dst_addr)
end
local function get_ipv4_src_ptr(ptr)
   return ptr + o_ipv4_src_addr
end
local function get_ipv4_src_address(ptr)
   return rd32(get_ipv4_src_ptr(ptr))
end
local function get_ipv6_next_header(ptr)
   return ptr[o_ipv6_next_header]
end
local function get_ether_dhost_ptr (pkt)
   return pkt.data
end
local function ether_equals (dst, src)
   return C.memcmp(dst, src, 6) == 0
end
local function get_ipv6_src_address(ptr)
   return ptr + o_ipv6_src_addr
end
local function copy_ether(dst, src)
   ffi.copy(dst, src, 6)
end

local function random_port ()
   return math.random(65535)
end

-- Set a bogus source IP address fe80::, so we can recognize it later when
-- it comes back from the VM.
--
-- Tried initially to use ::0 as source, but such packets are discarded
-- by the VM due to RFC 4007, chapter 9, which also considers the source IPv6
-- address.
--
-- Using the link local address fe80::, the packets are properly routed back
-- thru the same interface. Not sure if its OK to use that address or if there
-- is a better way.
--
local function ipv6_cache_trigger (pkt, mac)
   local ether_hdr = ethernet:new_from_mem(pkt.data, ethernet_header_size)
   local ipv6_hdr = ipv6:new_from_mem(pkt.data + ethernet_header_size, pkt.length - ethernet_header_size)
   local ipv6_payload_offset = ethernet_header_size + ipv6_fixed_header_size
   local ipv4_hdr = ipv4:new_from_mem(pkt.data + ipv6_payload_offset, pkt.length - ipv6_payload_offset)

   -- VM will discard packets not matching its MAC address on the interface.
   ether_hdr:dst(mac)
   -- Set a bogus source IP address.
   ipv6_hdr:src(n_cache_src_ipv6)

   -- Set random port.
   local tcp_hdr
   local tcp_offset = ipv6_payload_offset + ipv4_hdr:ihl() * 4
   local proto = ipv4_hdr:protocol()
   local payload_offset
   if proto == proto_tcp then
      tcp_hdr = tcp:new_from_mem(pkt.data + tcp_offset, pkt.length - tcp_offset)
      payload_offset = tcp_offset + tcp_hdr:sizeof()
   elseif proto == proto_udp then
      tcp_hdr = udp:new_from_mem(pkt.data + tcp_offset, pkt.length - tcp_offset)
      payload_offset = tcp_offset + tcp_hdr:sizeof()
   end
   tcp_hdr:src_port(random_port())
   -- Recalculate checksum.
   ipv4_hdr:checksum()
   tcp_hdr:checksum(pkt.data + payload_offset, pkt.length - payload_offset, ipv4_hdr)

   return pkt
end

local function send_ipv6_cache_trigger (r, pkt, mac)
   transmit(r, ipv6_cache_trigger(pkt, mac))
end

local function ipv4_cache_trigger (pkt, mac)
   local ether_hdr = ethernet:new_from_mem(pkt.data, ethernet_header_size)
   local ip_hdr = ipv4:new_from_mem(pkt.data + ethernet_header_size, pkt.length - ethernet_header_size)

   -- VM will discard packets not matching its MAC address on the interface.
   ether_hdr:dst(mac)
   -- Set a bogus source IP address.
   ip_hdr:src(n_cache_src_ipv4)
   -- Set random port.
   local tcp_hdr
   local tcp_offset = ethernet_header_size + (ip_hdr:ihl() * 4)
   local proto = ip_hdr:protocol()
   local payload_offset
   if proto == proto_tcp then
      tcp_hdr = tcp:new_from_mem(pkt.data + tcp_offset, pkt.length - tcp_offset)
      payload_offset = tcp_offset + tcp_hdr:sizeof()
   elseif proto == proto_udp then
      tcp_hdr = udp:new_from_mem(pkt.data + tcp_offset, pkt.length - tcp_offset)
      payload_offset = tcp_offset + tcp_hdr:sizeof()
   end
   tcp_hdr:dst_port(random_port())
   -- Recalculate checksum.
   ip_hdr:checksum()
   tcp_hdr:checksum(pkt.data + payload_offset, pkt.length - payload_offset, ip_hdr)

   return pkt
end

local function send_ipv4_cache_trigger (r, pkt, mac)
   transmit(r, ipv4_cache_trigger(pkt, mac))
end

function nh_fwd4:new (conf)
   local mac_address = ethernet:pton(conf.mac_address)
   local ipv4_address = rd32(ipv4:pton(conf.ipv4_address))
   local service_mac = conf.service_mac and ethernet:pton(conf.service_mac)
   local debug = conf.debug
   print(string.format("nh_fwd4: cache_refresh_interval set to %d seconds",
                      conf.cache_refresh_interval))

   local next_hop_mac = shm.create("next_hop_mac_v4", "struct { uint8_t ether[6]; }")
   if conf.next_hop_mac then
      next_hop_mac = ethernet:pton(conf.next_hop_mac)
      print(("nh_fwd4: static next_hop_mac %s"):format(ethernet:ntop(next_hop_mac)))
   end

   local o = {
      mac_address = mac_address,
      next_hop_mac = next_hop_mac,
      ipv4_address = ipv4_address,
      service_mac = service_mac,
      debug = conf.debug,
      cache_refresh_time = 0,
      cache_refresh_interval = conf.cache_refresh_interval
   }
   return setmetatable(o, {__index = nh_fwd4})
end

function nh_fwd4:push ()
   local input_service, output_service = self.input.service, self.output.service
   local input_wire, output_wire = self.input.wire, self.output.wire
   local input_vm, output_vm = self.input.vm, self.output.vm

   local next_hop_mac = self.next_hop_mac
   local service_mac = self.service_mac
   local mac_address = self.mac_address
   local current_time = tonumber(app.now())

   -- IPv4 from Wire.
   if input_wire then
      for _ = 1, link.nreadable(input_wire) do
         local pkt = receive(input_wire)
         local ipv4_address = self.ipv4_address
         local ipv4_hdr = get_ethernet_payload(pkt)

         if get_ethertype(pkt) == n_ethertype_ipv4 and
               get_ipv4_dst_address(ipv4_hdr) ~= ipv4_address then
            transmit(output_service, pkt)
         elseif output_vm then
            transmit(output_vm, pkt)
         else
            packet.free(pkt)
         end
      end
   end

   -- IPv4 from VM.
   if input_vm then
      for _ = 1, link.nreadable(input_vm) do
         local pkt = receive(input_vm)
         local ether_dhost = get_ether_dhost_ptr(pkt)
         local ipv4_hdr = get_ethernet_payload(pkt)

         if service_mac and ether_equals(ether_dhost, service_mac) then
            transmit(output_service, pkt)
         elseif self.cache_refresh_interval > 0 and
                  get_ipv4_src_address(ipv4_hdr) == val_cache_src_ipv4 then
            -- Our magic cache next-hop resolution packet. Never send this out.

            copy_ether(self.next_hop_mac, ether_dhost)
            if self.debug then
               print(("nh_fwd4: learning next-hop '%s'"):format(ethernet:ntop(ether_dhost)))
            end
            packet.free(pkt)
         else
            transmit(output_wire, pkt)
         end
      end
   end

   -- IPv4 from Service.
   if input_service then
      for _ = 1, link.nreadable(input_service) do
         local pkt = receive(input_service)
         local ether_dhost = get_ether_dhost_ptr(pkt)

         if self.cache_refresh_interval > 0 and output_vm then
            if current_time > self.cache_refresh_time + self.cache_refresh_interval then
               self.cache_refresh_time = current_time
               send_ipv4_cache_trigger(output_vm, packet.clone(pkt), mac_address)
            end
         end

         -- Only use a cached, non-empty, mac address.
         if not ether_equals(next_hop_mac, n_next_hop_mac_empty) then
            -- Set nh mac and send the packet out the wire.
            copy_ether(ether_dhost, next_hop_mac)
            transmit(output_wire, pkt)
         elseif self.cache_refresh_interval == 0 and output_vm then
            -- Set nh mac matching the one for the vm.
            copy_ether(ether_dhost, next_hop_mac)
            transmit(output_vm, pkt)
         else
            packet.free(pkt)
         end
      end
   end
end

function nh_fwd6:new (conf)
   local mac_address = ethernet:pton(conf.mac_address)
   local service_mac = conf.service_mac and ethernet:pton(conf.service_mac)
   print(string.format("nh_fwd6: cache_refresh_interval set to %d seconds",
                      conf.cache_refresh_interval))

   local next_hop_mac = shm.create("next_hop_mac_v6", "struct { uint8_t ether[6]; }")
   if conf.next_hop_mac then
      next_hop_mac = ethernet:pton(conf.next_hop_mac)
      print(("nh_fwd6: static next_hop_mac %s"):format(ethernet:ntop(next_hop_mac)))
   end

   local o = {
      mac_address = mac_address,
      next_hop_mac = next_hop_mac,
      service_mac = service_mac,
      debug = conf.debug,
      cache_refresh_time = 0,
      cache_refresh_interval = conf.cache_refresh_interval
   }
   return setmetatable(o, {__index = nh_fwd6})
end

function nh_fwd6:push ()
   local input_service, output_service = self.input.service, self.output.service
   local input_wire, output_wire = self.input.wire, self.output.wire
   local input_vm, output_vm = self.input.vm, self.output.vm

   local next_hop_mac = self.next_hop_mac
   local service_mac = self.service_mac
   local mac_address = self.mac_address
   local current_time = tonumber(app.now())

   -- IPv6 from Wire.
   if input_wire then
      for _ = 1, link.nreadable(input_wire) do
         local pkt = receive(input_wire)
         local ipv6_header = get_ethernet_payload(pkt)
         local proto = get_ipv6_next_header(ipv6_header)

         if proto == proto_ipv4 or proto == ipv6_frag then
            transmit(output_service, pkt)
         elseif output_vm then
            transmit(output_vm, pkt)
         else
            packet.free(pkt)
         end
      end
   end

   -- IPv6 from VM.
   if input_vm then
      for _ = 1, link.nreadable(input_vm) do
         local pkt = receive(input_vm)
         local ether_dhost = get_ether_dhost_ptr(pkt)
         local ipv6_hdr = get_ethernet_payload(pkt)

         if service_mac and ether_equals(ether_dhost, service_mac) then
            transmit(output_service, pkt)
         elseif self.cache_refresh_interval > 0 and
                  ipv6_equals(get_ipv6_src_address(ipv6_hdr), n_cache_src_ipv6) then
            copy_ether(self.next_hop_mac, ether_dhost)
            if self.debug then
               print(("nh_fwd6: learning next-hop %s"):format(ethernet:ntop(self.next_hop_mac)))
            end
            packet.free(pkt)
         else
            transmit(output_wire, pkt)
         end
      end
   end

   -- IPv6 from Service.
   if input_service then
      for _ = 1, link.nreadable(input_service) do
         local pkt = receive(input_service)
         local ether_dhost = get_ether_dhost_ptr(pkt)

         if self.cache_refresh_interval > 0 and output_vm then
            if current_time > self.cache_refresh_time + self.cache_refresh_interval then
               self.cache_refresh_time = current_time
               send_ipv6_cache_trigger(output_vm, packet.clone(pkt), mac_address)
            end
         end

         -- Only use a cached, non-empty, mac address.
         if not ether_equals(next_hop_mac, n_next_hop_mac_empty) then
            -- Set next-hop MAC and send the packet out the wire.
            copy_ether(ether_dhost, next_hop_mac)
            transmit(output_wire, pkt)
         elseif self.cache_refresh_interval == 0 and output_vm then
            -- Set next-hop MAC matching the one for the VM.
            copy_ether(ether_dhost, next_hop_mac)
            transmit(output_vm, pkt)
         else
            packet.free(pkt)
         end
      end
   end
end

-- Unit tests.

local function transmit_packets (l, pkts)
   for _, pkt in ipairs(pkts) do
      link.transmit(l, packet.from_string(pkt))
   end
end

-- Test Wire to VM and Service.
local function test_ipv4_wire_to_vm_and_service (pkts)
   local c = config.new()
   config.app(c, 'source', basic_apps.Join)
   config.app(c, 'sink', basic_apps.Sink)
   config.app(c, 'nh_fwd', nh_fwd4, {
      mac_address = "52:54:00:00:00:01",
      service_mac = "02:aa:aa:aa:aa:aa",
      ipv4_address = "10.0.1.1",
   })
   config.link(c, 'source.out -> nh_fwd.wire')
   config.link(c, 'nh_fwd.service -> sink.in1')
   config.link(c, 'nh_fwd.vm -> sink.in2')

   engine.configure(c)
   transmit_packets(engine.app_table.source.output.out, pkts)
   engine.main({duration = 0.1, noreport = true})
   assert(link.stats(engine.app_table.sink.input.in1).rxpackets == 1)
   assert(link.stats(engine.app_table.sink.input.in2).rxpackets == 1)
end

-- Test VM to Service and Wire.
local function test_ipv4_vm_to_service_and_wire(pkts)
   engine.configure(config.new()) -- Clean up engine.
   local c = config.new()
   config.app(c, 'source', basic_apps.Join)
   config.app(c, 'sink', basic_apps.Sink)
   config.app(c, 'nh_fwd', nh_fwd4, {
      mac_address = "52:54:00:00:00:01",
      service_mac = "02:aa:aa:aa:aa:aa",
      ipv4_address = "10.0.1.1",
   })
   config.link(c, 'source.out -> nh_fwd.vm')
   config.link(c, 'nh_fwd.service -> sink.in1')
   config.link(c, 'nh_fwd.wire -> sink.in2')

   engine.configure(c)
   transmit_packets(engine.app_table.source.output.out, pkts)
   engine.main({duration = 0.1, noreport = true})
   assert(link.stats(engine.app_table.sink.input.in1).rxpackets == 1)
   assert(link.stats(engine.app_table.sink.input.in2).rxpackets == 1)
end

-- Test input Service -> Wire.
local function test_ipv4_service_to_wire (pkts)
   local c = config.new()
   config.app(c, 'source', basic_apps.Join)
   config.app(c, 'sink', basic_apps.Sink)
   config.app(c, 'nh_fwd', nh_fwd4, {
      mac_address = "52:54:00:00:00:01",
      service_mac = "02:aa:aa:aa:aa:aa",
      ipv4_address = "10.0.1.1",
      next_hop_mac = "52:54:00:00:00:02",
   })
   config.link(c, 'source.out -> nh_fwd.service')
   config.link(c, 'nh_fwd.wire -> sink.in1')

   engine.configure(c)
   transmit_packets(engine.app_table.source.output.out, pkts)
   engine.main({duration = 0.1, noreport = true})
   assert(link.stats(engine.app_table.sink.input.in1).rxpackets == 1)
end

-- Test input Service -> VM.
local function test_ipv4_service_to_vm (pkts)
   local c = config.new()
   config.app(c, 'source', basic_apps.Join)
   config.app(c, 'sink', basic_apps.Sink)
   config.app(c, 'nh_fwd', nh_fwd4, {
      mac_address = "52:54:00:00:00:01",
      service_mac = "02:aa:aa:aa:aa:aa",
      ipv4_address = "10.0.1.1",
   })
   config.link(c, 'source.out -> nh_fwd.service')
   config.link(c, 'nh_fwd.vm -> sink.in1')

   engine.configure(c)
   transmit_packets(engine.app_table.source.output.out, pkts)
   engine.main({duration = 0.1, noreport = true})
   assert(link.stats(engine.app_table.sink.input.in1).rxpackets == 1)
end

local function flush ()
   C.sleep(0.5)
   engine.configure(config.new())
end

local function test_ipv4_flow ()
   local pkt1 = lib.hexundump ([[
      02:aa:aa:aa:aa:aa 02:99:99:99:99:99 08 00 45 00
      02 18 00 00 00 00 0f 11 d3 61 0a 0a 0a 01 c1 05
      01 64 30 39 04 00 00 26 00 00 00 00 00 00 00 00
      00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
      00 00 00 00 00 00 00 00
   ]], 72)
   local pkt2 = lib.hexundump ([[
      ff ff ff ff ff ff a0 88 b4 2c fa ac 08 06 00 01
      08 00 06 04 00 01 a0 88 b4 2c fa ac c0 a8 00 0a
      00 00 00 00 00 00 0a 00 01 01
   ]], 42)
   test_ipv4_wire_to_vm_and_service({pkt1, pkt2})
   flush()
   test_ipv4_vm_to_service_and_wire({pkt1, pkt2})
   flush()
   test_ipv4_service_to_wire({pkt1})
   flush()
   test_ipv4_service_to_vm({pkt1})
   flush()
end

local function test_ipv6_wire_to_vm_and_service (pkts)
   local c = config.new()
   config.app(c, 'source', basic_apps.Join)
   config.app(c, 'sink', basic_apps.Sink)
   config.app(c, 'nh_fwd', nh_fwd6, {
      mac_address = "52:54:00:00:00:01",
      service_mac = "02:aa:aa:aa:aa:aa",
   })
   config.link(c, 'source.out -> nh_fwd.wire')
   config.link(c, 'nh_fwd.service -> sink.in1')
   config.link(c, 'nh_fwd.vm -> sink.in2')

   engine.configure(c)
   transmit_packets(engine.app_table.source.output.out, pkts)
   engine.main({duration = 0.1, noreport = true})
   assert(link.stats(engine.app_table.sink.input.in1).rxpackets == 1)
   assert(link.stats(engine.app_table.sink.input.in2).rxpackets == 1)
end

-- Test VM to Service and Wire.
local function test_ipv6_vm_to_service_and_wire(pkts)
   engine.configure(config.new()) -- Clean up engine.
   local c = config.new()
   config.app(c, 'source', basic_apps.Join)
   config.app(c, 'sink', basic_apps.Sink)
   config.app(c, 'nh_fwd', nh_fwd6, {
      mac_address = "52:54:00:00:00:01",
      service_mac = "02:aa:aa:aa:aa:aa",
   })
   config.link(c, 'source.out -> nh_fwd.vm')
   config.link(c, 'nh_fwd.service -> sink.in1')
   config.link(c, 'nh_fwd.wire -> sink.in2')

   engine.configure(c)
   transmit_packets(engine.app_table.source.output.out, pkts)
   engine.main({duration = 0.1, noreport = true})
   assert(link.stats(engine.app_table.sink.input.in1).rxpackets == 1)
   assert(link.stats(engine.app_table.sink.input.in2).rxpackets == 1)
end

-- Test input Service -> Wire.
local function test_ipv6_service_to_wire (pkts)
   local c = config.new()
   config.app(c, 'source', basic_apps.Join)
   config.app(c, 'sink', basic_apps.Sink)
   config.app(c, 'nh_fwd', nh_fwd6, {
      mac_address = "52:54:00:00:00:01",
      service_mac = "02:aa:aa:aa:aa:aa",
      next_hop_mac = "52:54:00:00:00:02",
   })
   config.link(c, 'source.out -> nh_fwd.service')
   config.link(c, 'nh_fwd.wire -> sink.in1')

   engine.configure(c)
   transmit_packets(engine.app_table.source.output.out, pkts)
   engine.main({duration = 0.1, noreport = true})
   assert(link.stats(engine.app_table.sink.input.in1).rxpackets == 1)
end

-- Test input Service -> VM.
local function test_ipv6_service_to_vm (pkts)
   local c = config.new()
   config.app(c, 'source', basic_apps.Join)
   config.app(c, 'sink', basic_apps.Sink)
   config.app(c, 'nh_fwd', nh_fwd6, {
      mac_address = "52:54:00:00:00:01",
      service_mac = "02:aa:aa:aa:aa:aa",
   })
   config.link(c, 'source.out -> nh_fwd.service')
   config.link(c, 'nh_fwd.vm -> sink.in1')

   engine.configure(c)
   transmit_packets(engine.app_table.source.output.out, pkts)
   engine.main({duration = 0.1, noreport = true})
   assert(link.stats(engine.app_table.sink.input.in1).rxpackets == 1)
end

local function test_ipv6_flow ()
   local pkt1 = lib.hexundump ([[
      02:aa:aa:aa:aa:aa 02:99:99:99:99:99 86 dd 60 00
      01 f0 01 f0 04 ff fc 00 00 01 00 02 00 03 00 04
      00 05 00 00 00 7e fc 00 00 00 00 00 00 00 00 00
      00 00 00 00 01 00 45 00 01 f0 00 00 00 00 0f 11
      d3 89 c1 05 01 64 0a 0a 0a 01 04 00 30 39 00 0c
      00 00 00 00 00 00
   ]], 86)
   local pkt2 = lib.hexundump ([[
      33:33:ff:00:00:01 f0:de:f1:61:b6:22 86 dd 60 00
      00 00 00 20 3a ff fe 80 00 00 00 00 00 00 f2 de
      f1 ff fe 61 b6 22 ff 02 00 00 00 00 00 00 00 00
      00 01 ff 00 00 01 87 00 4a d4 00 00 00 00 fe 80
      00 00 00 00 00 00 00 00 00 00 00 00 00 01 01 01
      f0 de f1 61 b6 22
   ]], 86)
   test_ipv6_wire_to_vm_and_service({pkt1, pkt2})
   flush()
   test_ipv6_vm_to_service_and_wire({pkt1, pkt2})
   flush()
   test_ipv6_service_to_wire({pkt1})
   flush()
   test_ipv6_service_to_vm({pkt1})
end

local function test_ipv4_cache_trigger (pkt)
   local checksum = require("lib.checksum")
   local ether_dhost = "52:54:00:00:00:01"
   local refresh_packet = ipv4_cache_trigger(pkt, ethernet:pton(ether_dhost))
   local eth_hdr = ethernet:new_from_mem(refresh_packet.data, ethernet_header_size)
   local ip_hdr = ipv4:new_from_mem(refresh_packet.data + ethernet_header_size,
      refresh_packet.length - ethernet_header_size)
   assert(ip_hdr:src_eq(n_cache_src_ipv4))
   assert(ethernet:ntop(eth_hdr:dst()) == ether_dhost)
   assert(checksum.verify_packet(refresh_packet.data + ethernet_header_size,
      refresh_packet.length - ethernet_header_size))
end

local function test_ipv6_cache_trigger (pkt)
   local checksum = require("lib.checksum")
   local ether_dhost = "52:54:00:00:00:01"
   local refresh_packet = ipv6_cache_trigger(pkt, ethernet:pton(ether_dhost))
   local eth_hdr = ethernet:new_from_mem(refresh_packet.data, ethernet_header_size)
   local ip_hdr = ipv6:new_from_mem(refresh_packet.data + ethernet_header_size,
      refresh_packet.length - ethernet_header_size)
   assert(ip_hdr:src_eq(n_cache_src_ipv6))
   assert(ethernet:ntop(eth_hdr:dst()) == ether_dhost)
   local payload_offset = ethernet_header_size + ipv6_fixed_header_size
   local ipv4_pkt = refresh_packet.data + payload_offset
   local ipv4_pkt_length = refresh_packet.length - payload_offset
   assert(checksum.verify_packet(ipv4_pkt, ipv4_pkt_length))
end

local function ipv4_udp_pkt ()
   return packet.from_string(lib.hexundump([[
      02:aa:aa:aa:aa:aa 02:99:99:99:99:99 08 00 45 00
      02 18 00 00 00 00 0f 11 d3 61 0a 0a 0a 01 c1 05
      01 64 30 39 04 00 00 26 00 00 00 00 00 00 00 00
      00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
      00 00 00 00 00 00 00 00
   ]], 72))
end

local function ipv4_tcp_pkt ()
   return packet.from_string(lib.hexundump([[
      18 55 0f ae d0 1d a0 88 b4 2c fa ac 08 00 45 00
      00 34 b8 a0 40 00 40 06 69 55 c0 a8 00 11 97 65
      c0 af e5 97 00 50 15 91 83 d6 5d 31 61 91 80 10
      02 a9 ff 98 00 00 01 01 08 0a 07 c3 3c f9 47 c4
      91 1a
   ]], 66))
end

local function ipv6_udp_pkt ()
   return packet.from_string(lib.hexundump([[
      02:aa:aa:aa:aa:aa 02:99:99:99:99:99 86 dd 60 00
      01 f0 01 f0 04 ff fc 00 00 01 00 02 00 03 00 04
      00 05 00 00 00 7e fc 00 00 00 00 00 00 00 00 00
      00 00 00 00 01 00 45 00 01 f0 00 00 00 00 0f 11
      d3 89 c1 05 01 64 0a 0a 0a 01 04 00 30 39 00 0c
      00 00 00 00 00 00
   ]], 86))
end

local function ipv6_tcp_pkt ()
   return packet.from_string(lib.hexundump([[
      02 aa aa aa aa aa 02 99 99 99 99 99 86 dd 60 00
      01 f0 01 f0 04 ff fc 00 00 01 00 02 00 03 00 04
      00 05 00 00 00 7e fc 00 00 00 00 00 00 00 00 00
      00 00 00 00 01 00 45 00 00 34 b8 a0 40 00 40 06
      69 55 c0 a8 00 11 97 65 c0 af e5 97 00 50 15 91
      83 d6 5d 31 61 91 80 10 02 a9 ff 98 00 00 01 01
      08 0a 07 c3 3c f9 47 c4 91 1a
   ]], 106))
end

function selftest ()
   print("nh_fwd: selftest")
   test_ipv4_flow()
   test_ipv6_flow()
   test_ipv4_cache_trigger(ipv4_udp_pkt())
   test_ipv4_cache_trigger(ipv4_tcp_pkt())
   test_ipv6_cache_trigger(ipv6_udp_pkt())
   test_ipv6_cache_trigger(ipv6_tcp_pkt())
end
