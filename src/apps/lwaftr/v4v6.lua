module(..., package.seeall)

local constants = require("apps.lwaftr.constants")
local lwutil = require("apps.lwaftr.lwutil")
local shm = require("core.shm")

local transmit, receive = link.transmit, link.receive
local rd16, rd32 = lwutil.rd16, lwutil.rd32

local ethernet_header_size = constants.ethernet_header_size
local n_ethertype_ipv4 = constants.n_ethertype_ipv4
local o_ethernet_ethertype = constants.o_ethernet_ethertype
local o_ipv4_dst_addr = constants.o_ipv4_dst_addr
local o_ipv4_src_addr = constants.o_ipv4_src_addr
local ipv6_fixed_header_size = constants.ipv6_fixed_header_size

local v4v6_mirror = shm.create("v4v6_mirror", "struct { uint32_t ipv4; }")

local function is_ipv4 (pkt)
   return rd16(pkt.data + o_ethernet_ethertype) == n_ethertype_ipv4
end
local function get_ethernet_payload (pkt)
   return pkt.data + ethernet_header_size
end
local function get_ipv4_dst_num (ptr)
   return rd32(ptr + o_ipv4_dst_addr)
end
local function get_ipv4_src_num (ptr)
   return rd32(ptr + o_ipv4_src_addr)
end
local function get_ipv6_payload (ptr)
   return ptr + ipv6_fixed_header_size
end

local function mirror_ipv4 (pkt, output, ipv4_num)
   local ipv4_hdr = get_ethernet_payload(pkt)
   if get_ipv4_dst_num(ipv4_hdr) == ipv4_num or
         get_ipv4_src_num(ipv4_hdr) == ipv4_num then
      transmit(output, packet.clone(pkt))
   end
end

local function mirror_ipv6 (pkt, output, ipv4_num)
   local ipv6_hdr = get_ethernet_payload(pkt)
   local ipv4_hdr = get_ipv6_payload(ipv6_hdr)
   if get_ipv4_dst_num(ipv4_hdr) == ipv4_num or
         get_ipv4_src_num(ipv4_hdr) == ipv4_num then
      transmit(output, packet.clone(pkt))
   end
end

v4v6 = {}

function v4v6:new (conf)
   local o = {
      description = conf.description or "v4v6",
      mirror = conf.mirror or false,
   }
   return setmetatable(o, {__index = v4v6})
end

function v4v6:push()
   local input, output = self.input.input, self.output.output
   local v4_tx, v6_tx = self.output.v4_tx, self.output.v6_tx
   local v4_rx, v6_rx = self.input.v4_rx, self.input.v6_rx
   local mirror = self.output.mirror

   local ipv4_num
   if self.mirror then
      mirror = self.output.mirror
      ipv4_num = v4v6_mirror.ipv4
   end

   -- Split input to IPv4 and IPv6 traffic.
   while not link.empty(input) do
      local pkt = receive(input)
      if is_ipv4(pkt) then
         if mirror then
            mirror_ipv4(pkt, mirror, ipv4_num)
         end
         transmit(v4_tx, pkt)
      else
         if mirror then
            mirror_ipv6(pkt, mirror, ipv4_num)
         end
         transmit(v6_tx, pkt)
      end
   end

   -- Join IPv4 and IPv6 traffic to output.
   while not link.empty(v4_rx) do
      local pkt = receive(v4_rx)
      if mirror and not link.full(mirror) then
         mirror_ipv4(pkt, mirror, ipv4_num)
      end
      transmit(output, pkt)
   end
   while not link.empty(v6_rx) do
      local pkt = receive(v6_rx)
      if mirror then
         mirror_ipv6(pkt, mirror, ipv4_num)
      end
      transmit(output, pkt)
   end
end
