module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local app = require("core.app")
local packet = require("core.packet")
local pcap = require("apps.pcap.pcap")
local Buzz = require("apps.basic.basic_apps").Buzz

local ipv6_t = ffi.typeof[[
struct {
   // ethernet
   char dmac[6];
   char smac[6];
   uint16_t ethertype;
   // ipv6
   int32_t flow_id;
   int16_t payload_length;
   int8_t  next_header;
   uint8_t hop_limit;
   char src_ip[16];
   char dst_ip[16];
} __attribute__((packed)) *
]]

local icmpv6_t = ffi.typeof[[
struct {
   uint8_t type;
   uint8_t code;
   int16_t checksum;
   union {
      struct {
         uint16_t reserved;
         char target_address[16];
      } solicit;
      struct {
         int r:1, s:1, o:1, reserved:29;
         char target_address[16];
      } advert;
   };
   // option: link layer address
   struct {
      uint8_t type;
      uint8_t length;
      char addr[6];
   } l2addr;
} __attribute__((packed)) *
]]

SimpleIPv6 = {}

function SimpleIPv6:new (own_mac, own_ip)
   local o = {own_mac = own_mac, own_ip = own_ip}
   return setmetatable(o, {__index = SimpleIPv6})
end

function SimpleIPv6:push ()
   for name, iport in pairs(self.input) do
      -- Output to the port with the same name as the input port (e.g. "eth0")
      local oport = self.output[name]
      assert(oport, "output port not found")
      for i = 1, app.nreadable(iport) do
         local p = app.receive(iport)
         assert(p.iovecs[0].length >= ffi.sizeof(ipv6_t))
         local ipv6 = ffi.cast(ipv6_t, p.iovecs[0].buffer.pointer + p.iovecs[0].offset)
         if ipv6.ethertype == 0xDD86 then -- IPv6 (host byte order) then
            -- Sent to this app?
            if ipv6.hop_limit > 1 then
               if ipv6.next_header == 58 then -- ICMPv6
                  print("Received ICMPv6")
                  local ptr = p.iovecs[0].buffer.pointer + p.iovecs[0].offset + 54
                  local icmpv6 = ffi.cast(icmpv6_t, ptr)
                  if icmpv6.type == 135 then -- neighbor solicitation
                     print("  Responding to neighbor solicitation.")
                     -- Convert the solicitation into an advertisment.
                     icmpv6.type = 136 -- neighbor adverisment
                     icmpv6.l2addr.type = 2 -- target address
                     ffi.copy(icmpv6.l2addr.addr, self.own_mac, 6)
                     ffi.copy(ipv6.dst_ip, ipv6.src_ip, 16)
                     ffi.copy(ipv6.src_ip, self.own_ip, 16)
                     ffi.copy(ipv6.dmac, ipv6.smac, 6)
                     ffi.copy(ipv6.smac, self.own_mac, 6)
                     -- Transmit
                     app.transmit(oport, p)
                  end
               elseif C.memcmp(self.own_mac, ipv6.dmac, 6) == 0 then
                  -- Example: "Route" packet back to source.
                  -- (rewrite dmac, decrement hop limit)
                  ffi.copy(ipv6.dmac, ipv6.smac, 6)
                  ipv6.hop_limit = ipv6.hop_limit - 1
                  app.transmit(oport, p)
               else
                  -- Out of hops!
                  -- Send ICMP
                  -- Drop packet
                  packet.deref(p)
               end
            end
         else
            print("unknown ethertype: " .. bit.tohex(ipv6.ethertype, 4))
            for i = 0, 5 do
               print(ipv6.smac[i])
            end
            -- Drop packet
            packet.deref(p)
         end
      end
   end
end

function selftest ()
   print("selftest: ipv6")
   local own_ip = "\x20\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01"
   local own_mac = "\x52\x54\x00\x12\x34\x57"
   app.apps.source = app.new(pcap.PcapReader:new("apps/ipv6/selftest.cap"))
   app.apps.ipv6   = app.new(SimpleIPv6:new(own_mac, own_ip))
   app.apps.sink   = app.new(pcap.PcapWriter:new("apps/ipv6/selftest-output.cap"))
   app.connect("source", "output", "ipv6", "eth0")
   app.connect("ipv6", "eth0",     "sink", "input")
   app.relink()
   for i = 1, 10 do  app.breathe()  end
   app.report()
   print("OK.")
end

