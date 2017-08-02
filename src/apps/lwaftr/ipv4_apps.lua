module(..., package.seeall)

local constants = require("apps.lwaftr.constants")
local fragmentv4 = require("apps.lwaftr.fragmentv4")
local lwutil = require("apps.lwaftr.lwutil")
local icmp = require("apps.lwaftr.icmp")
local lwcounter = require("apps.lwaftr.lwcounter")

local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")
local checksum = require("lib.checksum")
local packet = require("core.packet")
local lib = require("core.lib")
local counter = require("core.counter")
local link = require("core.link")
local engine = require("core.app")

local receive, transmit = link.receive, link.transmit
local wr16, rd32, wr32 = lwutil.wr16, lwutil.rd32, lwutil.wr32
local get_ihl_from_offset = lwutil.get_ihl_from_offset
local is_ipv4 = lwutil.is_ipv4
local htons = lib.htons

local ehs = constants.ethernet_header_size
local o_ipv4_ver_and_ihl = ehs + constants.o_ipv4_ver_and_ihl
local o_ipv4_checksum = ehs + constants.o_ipv4_checksum
local o_icmpv4_msg_type_sans_ihl = ehs + constants.o_icmpv4_msg_type
local o_icmpv4_checksum_sans_ihl = ehs + constants.o_icmpv4_checksum
local icmpv4_echo_request = constants.icmpv4_echo_request
local icmpv4_echo_reply = constants.icmpv4_echo_reply

Fragmenter = {}
ICMPEcho = {}

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
