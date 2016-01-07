module(..., package.seeall)

local constants = require("apps.lwaftr.constants")
local fragmentv4 = require("apps.lwaftr.fragmentv4")
local lwutil = require("apps.lwaftr.lwutil")

local packet = require("core.packet")
local bit = require("bit")
local ffi = require("ffi")

local receive, transmit = link.receive, link.transmit
local rd16 = lwutil.rd16
local is_fragment = fragmentv4.is_fragment

local n_ethertype_ipv4 = constants.n_ethertype_ipv4
local o_ipv4_identification = constants.o_ipv4_identification
local o_ipv4_src_addr = constants.o_ipv4_src_addr
local o_ipv4_dst_addr = constants.o_ipv4_dst_addr

Reassembler = {}
Fragmenter = {}

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

function Reassembler:key_frag(frag)
   local frag_id = rd16(frag.data + self.l2_size + o_ipv4_identification)
   local src_ip = ffi.string(frag.data + self.l2_size + o_ipv4_src_addr, 4)
   local dst_ip = ffi.string(frag.data + self.l2_size + o_ipv4_dst_addr, 4)
   return frag_id .. "|" .. src_ip .. dst_ip
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

local function is_ipv4(pkt, ethertype_offset)
   return rd16(pkt.data + ethertype_offset) == n_ethertype_ipv4
end

function Reassembler:push ()
   local input, output = self.input.input, self.output.output
   local errors = self.output.errors

   local l2_size = self.l2_size
   local ethertype_offset = self.ethertype_offset

   for _=1,math.min(link.nreadable(input), link.nwritable(output)) do
      local pkt = receive(input)
      if is_ipv4(pkt, ethertype_offset) and is_fragment(pkt, l2_size) then
         local frags = self:cache_fragment(pkt)
         local status, maybe_pkt = fragmentv4.reassemble(frags, l2_size)
         if status == fragmentv4.REASSEMBLE_OK then
            -- Reassembly was successful
            self:clean_fragment_cache(frags)
            transmit(output, maybe_pkt)
         elseif status == fragmentv4.REASSEMBLE_MISSING_FRAGMENT then
            -- Nothing to do, just wait.
         else
            assert(frag_status == fragmentv4.REASSEMBLE_INVALID)
            self:clean_fragment_cache(frags)
            if maybe_pkt then -- This is an ICMP packet
               transmit(errors, maybe_pkt)
            end
         end
      else
         -- Forward all packets that aren't IPv4 fragments.
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

   for _=1,math.min(link.nreadable(input), link.nwritable(output)) do
      local pkt = receive(input)
      if pkt.length > mtu + l2_size and is_ipv4(pkt, ethertype_offset) then
         local status, frags = fragmentv4.fragment(pkt, l2_size, mtu)
         if status == fragmentv4.FRAGMENT_OK then
            for i=1,#frags do transmit(output, frags[i]) end
         else
            -- TODO: send ICMPv4 info if allowed by policy
            packet.free(pkt)
         end
      else
         transmit(output, pkt)
      end
   end
end
