module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local app = require("core.app")
local link = require("core.link")
local config = require("core.config")
local lib = require("core.lib")
local packet = require("core.packet")
local buffer = require("core.buffer")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local pcap = require("apps.pcap.pcap")
local Buzz = require("apps.basic.basic_apps").Buzz

size = { eth = 14, ipv6 = 40, icmpv6expired = 8 }

local ipv6_t = ffi.typeof[[
struct {
   // ethernet
   char dmac[6];
   char smac[6];
   uint16_t ethertype;
   // ipv6
   uint32_t flow_id; // version, tc, flow_id
   int16_t payload_length;
   int8_t  next_header;
   uint8_t hop_limit;
   char src_ip[16];
   char dst_ip[16];
} __attribute__((packed))
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
      struct {
	 uint32_t unused;
	 char data[0];
      } timeout;
   };
   // option: link layer address
   struct {
      uint8_t type;
      uint8_t length;
      char addr[6];
   } l2addr;
} __attribute__((packed))
]]

SimpleIPv6 = {}

function SimpleIPv6:new (arg)
   local conf = arg and config.parse_app_arg(arg) or {}
   if type(conf.own_mac) == "string" then
      conf.own_mac = ethernet:pton(conf.own_mac)
   end
   own_mac = conf.own_mac or "52:54:00:12:34:57"
   if type(conf.own_ip) == "string" then
      conf.own_ip = ipv6:pton(conf.own_ip)
   end
   own_ip = conf.own_ip or "2::1"
   local o = {own_mac = own_mac, own_ip = own_ip}
   return setmetatable(o, {__index = SimpleIPv6})
end

function SimpleIPv6:push ()
   for name, iport in pairs(self.input) do
      -- Output to the port with the same name as the input port (e.g. "eth0")
      local oport = self.output[name]
      assert(oport, "output port not found")
      for i = 1, link.nreadable(iport) do
         local p = link.receive(iport)
         assert(p.iovecs[0].length >= ffi.sizeof(ipv6_t))
         local ipv6 = ffi.cast(ffi.typeof("$*", ipv6_t), p.iovecs[0].buffer.pointer + p.iovecs[0].offset)
         if ipv6.ethertype == 0xDD86 then -- IPv6 (host byte order) then
            if ipv6.hop_limit > 1 then
               if ipv6.next_header == 58 then -- ICMPv6
                  print("Received ICMPv6")
		  --assert(p.iovecs[0].length >= ffi.sizeof(ipv6_t) + ffi.sizeof(icmpv6_t))
                  local ptr = p.iovecs[0].buffer.pointer + p.iovecs[0].offset + 54
                  local icmpv6 = ffi.cast(ffi.typeof("$*", icmpv6_t), ptr)
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
		     checksum_icmpv6(ipv6, icmpv6)
                     -- Transmit
                     link.transmit(oport, p)
		  elseif icmpv6.type == 128 then -- echo
		     print("  Responding to ECHO request")
		     icmpv6.type = 129 -- echo response
                     ffi.copy(ipv6.dst_ip, ipv6.src_ip, 16)
                     ffi.copy(ipv6.src_ip, self.own_ip, 16)
                     ffi.copy(ipv6.dmac, ipv6.smac, 6)
                     ffi.copy(ipv6.smac, self.own_mac, 6)
		     checksum_icmpv6(ipv6, icmpv6)
		     link.transmit(oport, p)
                  end
               elseif C.memcmp(self.own_mac, ipv6.dmac, 6) == 0 then
                  -- Example: "Route" packet back to source.
                  -- (rewrite dmac, decrement hop limit)
                  ffi.copy(ipv6.dmac, ipv6.smac, 6)
                  ipv6.hop_limit = ipv6.hop_limit - 1
                  link.transmit(oport, p)
	       end
	    else
	       print("  Sending ICMPv6 Time Exceeded")
	       -- Out of hops!
	       local new_p = packet.allocate()
	       local new_b = buffer.allocate()
	       local new_ipv6 = ffi.cast(ffi.typeof("$*", ipv6_t),
					 new_b.pointer)
	       local excerpt_len = math.min(1280 - 62, p.iovecs[0].length - size.eth)
	       ffi.copy(new_ipv6.dmac, ipv6.smac, 6)
	       ffi.copy(new_ipv6.smac, self.own_mac, 6)
	       new_ipv6.ethertype = 0xDD86
	       new_ipv6.flow_id = 0x60 -- version=6
	       new_ipv6.payload_length = htons(size.icmpv6expired + excerpt_len)
	       new_ipv6.next_header = 58 -- icmpv6
	       new_ipv6.hop_limit = 255
	       ffi.copy(new_ipv6.src_ip, self.own_ip, 16)
	       ffi.copy(new_ipv6.dst_ip, ipv6.src_ip, 16)
	       local new_icmpv6 = ffi.cast(ffi.typeof("$*", icmpv6_t),
					   new_b.pointer + size.eth + size.ipv6)
	       new_icmpv6.type = 3
	       new_icmpv6.code = 0
	       new_icmpv6.timeout.unused = 0
	       -- copy excerpt
	       ffi.copy(new_b.pointer + size.eth + size.ipv6 + size.icmpv6expired,
			p.iovecs[0].buffer.pointer + size.eth,
			excerpt_len)
	       checksum_icmpv6(new_ipv6, new_icmpv6)
	       packet.add_iovec(new_p, new_b, size.eth + size.ipv6 + size.icmpv6expired + excerpt_len)
	       link.transmit(oport, new_p)
	       packet.deref(p)
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

function checksum_icmpv6 (ipv6, icmpv6, icmpv6_len)
   -- IPv6 pseudo-checksum
   local ipv6_ptr = ffi.cast("uint8_t*", ipv6)
   local csum = lib.update_csum(ipv6_ptr + ffi.offsetof(ipv6_t, 'src_ip'), 32)
   csum = lib.update_csum(ipv6_ptr + ffi.offsetof(ipv6_t, 'payload_length'), 2, csum)
   -- ICMPv6 checksum
   icmpv6.checksum = 0
   csum = lib.update_csum(icmpv6, htons(ipv6.payload_length), csum)
   csum = csum + 58
   icmpv6.checksum = htons(lib.finish_csum(csum))
end

function htons (n)
   return bit.lshift(bit.band(n, 0xff), 8) + bit.rshift(n, 8)
end
function ntohs (n)
   return htons(n)
end

function selftest ()
   print("selftest: ipv6")
   local own_ip = "2::1"
   local own_mac = "52:54:00:12:34:57"
   local c = config.new()
   config.app(c, "source", pcap.PcapReader, "apps/ipv6/selftest.cap.input")
   config.app(c, "ipv6", SimpleIPv6,
              { own_ip  = "2::1",
                own_mac = "52:54:00:12:34:57" })
   config.app(c, "sink", pcap.PcapWriter, "apps/ipv6/selftest.cap.output")
   config.link(c, "source.output -> ipv6.eth0")
   config.link(c, "ipv6.eth0 -> sink.input")
   app.configure(c)
   app.main({duration = 0.25}) -- should be long enough...
   -- Check results
   if io.open("apps/ipv6/selftest.cap.output"):read('*a') ~=
      io.open("apps/ipv6/selftest.cap.expect"):read('*a') then
      print([[file selftest.cap.output does not match selftest.cap.expect.
Check for the mismatch like this (example):
  tshark -Vnr apps/ipv6/selftest.cap.output > /tmp/selftest.cap.output.txt
  tshark -Vnr apps/ipv6/selftest.cap.expect > /tmp/selftest.cap.expect.txt
  diff -u /tmp/selftest.cap.{output,expect}.txt | less ]])
      print("selftest failed.")
      os.exit(1)
   else
      print("OK.")
   end
end

