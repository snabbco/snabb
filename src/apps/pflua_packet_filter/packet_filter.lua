module(...,package.seeall)

package.path = package.path .. ";../deps/pflua/src/?.lua"

local ffi = require("ffi")
local C = ffi.C
local bit = require("bit")

local app = require("core.app")
local link = require("core.link")
local lib = require("core.lib")
local packet = require("core.packet")
local buffer = require("core.buffer")
local config = require("core.config")

local pcap = require("apps.pcap.pcap")
local basic_apps = require("apps.basic.basic_apps")

local pflua = require("pf")

local verbose = false

assert(ffi.abi("le"), "support only little endian architecture at the moment")
assert(ffi.abi("64bit"), "support only 64 bit architecture at the moment")

local function compile_filters (filters)
   local result = {}
   for i, each in ipairs(filters) do
      result[i] = pflua.compile_filter(each)
   end
   return result
end

PacketFilter = {}

function PacketFilter:new (filters)
   assert(filters)
   assert(#filters > 0)

   local compiled_filters = compile_filters(filters)

   local function conform (buffer, length)
      for _, func in ipairs(compiled_filters) do
         if func(buffer, length) then
            return true
         end
      end
      return false
   end
   return setmetatable({ conform = conform }, { __index = PacketFilter })
end

function PacketFilter:push ()
   local i = assert(self.input.input or self.input.rx, "input port not found")
   local o = assert(self.output.output or self.output.tx, "output port not found")

   local packets_tx = 0
   local max_packets_to_send = link.nwritable(o)
   if max_packets_to_send == 0 then
      return
   end

   local nreadable = link.nreadable(i)
   for n = 1, nreadable do
      local p = link.receive(i)

      local buffer = p.iovecs[0].buffer.pointer + p.iovecs[0].offset
      local length = p.iovecs[0].length

      if self.conform(buffer, length) then
         link.transmit(o, p)
      else
         packet.deref(p)
      end
   end
end

function selftest ()
   -- Temporarily disabled:
   --   Packet filter selftest is failing in.
   -- enable verbose logging for selftest

   verbose = true
   buffer.preallocate(10000)

   local V6_RULE_ICMP_PACKETS = 3 -- packets within v6.pcap
   local V6_RULE_DNS_PACKETS =  3 -- packets within v6.pcap

   local v6_rules = {
   [[
      icmp6 and
      src net 3ffe:501:0:1001::2/128 and
      dst net 3ffe:507:0:1:200:86ff:fe05:8000/116
   ]],
   [[
      udp and
      src portrange 2397-2399 and
      dst port 53
   ]],
   }

   local c = config.new()
   config.app(
      c,
      "source1",
      pcap.PcapReader,
      "apps/packet_filter/samples/v6.pcap"
   )
   config.app(c,
      "packet_filter1",
      PacketFilter,
      v6_rules
   )
   config.app(c,  "sink1", basic_apps.Sink )
   config.link(c, "source1.output -> packet_filter1.input")
   config.link(c, "packet_filter1.output -> sink1.input")

   -- IPv4

   local V4_RULE_DNS_PACKETS = 1 -- packets within v4.pcap
   local V4_RULE_TCP_PACKETS = 18 -- packets within v4.pcap

   local v4_rules = {
   [[
      udp and
      dst port 53
   ]],
   [[
      tcp and
      src host 65.208.228.223 and
      src portrange 80-81 and
      dst net 145.240.0.0/12 and
      dst portrange 3371-3373
   ]],
   }

   config.app(
      c,
      "source2",
      pcap.PcapReader,
      "apps/packet_filter/samples/v4.pcap"
   )
   config.app(c,
      "packet_filter2",
      PacketFilter,
      v4_rules
   )
   config.app(c, "sink2", basic_apps.Sink )
   config.link(c, "source2.output -> packet_filter2.input")
   config.link(c, "packet_filter2.output -> sink2.input")

   -- v4.pcap contains 43 packets
   -- v6.pcap contains 161 packets
   -- one breathe is enough
   app.configure(c)
   app.breathe()
   app.report()

   local packets = {
      filter1 = { tx = app.app_table.packet_filter1.output.output.stats.txpackets },
      filter2 = { tx = app.app_table.packet_filter2.output.output.stats.txpackets },
   }

   local ok = true

   if packets.filter1.tx ~= V6_RULE_ICMP_PACKETS + V6_RULE_DNS_PACKETS then
      print("IPv6 test failed")
      ok = false
   end

   if packets.filter2.tx ~= V4_RULE_DNS_PACKETS + V4_RULE_TCP_PACKETS then
      print("IPv4 test failed")
      ok = false
   end

   if not ok then
      print("selftest failed")
      os.exit(1)
   end
   print("selftest passed")
end

PacketFilter.selftest = selftest

return PacketFilter
