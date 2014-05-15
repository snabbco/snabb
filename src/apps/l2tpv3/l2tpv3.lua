module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
local Tee = require("apps.basic.basic_apps").Tee
local ns_responder = require("apps.ipv6.ns_responder")
local pcap = require("apps.pcap.pcap")
local PcapReader, PcapWriter = pcap.PcapReader, pcap.PcapWriter
local RawSocket = require("apps.socket.raw")
local lib = require("core.lib")

-- Template for an L2TPv3 packet header. Constructed with code.
template = {}
-- Label->Position table of interesting data in the template.
labels = {}
-- Append data (hex string) to the template.
function D (hex)
   for b in hex:gmatch("[0-9a-fA-F][0-9a-fA-F]") do
      table.insert(template, tonumber(b, 16))
   end
end
-- Label the current position in the template by NAME.
function L (name)  labels[name] = #template  end

-- Template definition for an L2TPv3 packet encapsulation.
L"ETH.DST"  D"00 00 00 00 00 00"
L"ETH.SRC"  D"00 00 00 00 00 00"
L"ETH.PRO"  D"86 DD"		-- EtherType: IPv6
L"IPV6.VSN" D"60 00 00 00"	-- IP version, tc, flow id
L"IPV6.LEN" D"00 00"		-- Payload length
L"IPV6.NXT" D"73 FF"
L"IPV6.SRC" D"00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"
L"IPV6.DST" D"00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"
L"SESSION"  D"00 00 00 00"
L"COOKIE"   D"00 00 00 00 00 00 00 00"

local headersize = #template

function make_header ()
   return ffi.new("char[?]", #template, template)
end

function setbytes (header, label, value)
   if value ~= nil then
      local ptr = header+labels[label]
      for b in value:gmatch('[0-9a-fA-F][0-9a-fA-F]') do
	 ptr[0] = tonumber(b, 16)
	 ptr = ptr + 1
      end
   end
end

function setipv6addr (header, label, value)
   if value ~= nil then
      local AF_INET6 = 10
      C.inet_pton(AF_INET6, ffi.cast("char *", value), header+labels[label])
   end
end

L2TPv3 = {}

function L2TPv3:new (arg)
   local h = make_header()
   setbytes(h, "ETH.SRC", arg.eth_src)
   setbytes(h, "ETH.DST", arg.eth_dst)
   setbytes(h, "SESSION", arg.session)
   setbytes(h, "COOKIE",  arg.cookie)
   setipv6addr(h, "IPV6.SRC", arg.ipv6_src)
   setipv6addr(h, "IPV6.DST", arg.ipv6_dst)
   return setmetatable({header = h}, {__index = L2TPv3})
end

function L2TPv3:push ()
   local rx_encap, rx_decap = self.input.encap, self.input.decap
   local tx_encap, tx_decap = self.output.encap, self.output.decap
   while not link.empty(rx_decap) do
      local p = packet.want_modify(link.receive(rx_decap))
--      local p = link.receive(rx_decap)
      print("packet length", p.length)
      if p.length < 60 then
	 print("SHORT PACKET")
	 ffi.fill(p.iovecs[0].buffer.pointer + p.iovecs[0].offset + p.iovecs[0].length,
		  60 - p.length, 0)
	 p.iovecs[0].length = 60
	 p.length = 60
      end
      local len = p.length
      local wirelen = len + 12
      local b = buffer.allocate()
      local ptr = b.pointer
      ffi.copy(ptr, self.header, headersize)
      ptr[labels["IPV6.LEN"]+0] = bit.rshift(wirelen, 8)
      ptr[labels["IPV6.LEN"]+1] = wirelen % 256
--      ffi.cast(ptr + labels["IPV6.LEN"], "uint16_t*")[0] = C.htons(len)
--      print("[0]", ptr[0], self.header[0])
      packet.prepend_iovec(p, b, headersize)
--      print("encap len", p.length)
      link.transmit(tx_encap, p)
   end
   while not link.empty(rx_encap) do
      local p = packet.want_modify(link.receive(rx_encap))
--      local p = link.receive(rx_encap)
      local iovec = p.iovecs[0]
      local ptr = iovec.buffer.pointer
--      if ffi.cast(ptr + labels["ETH.PRO"], "uint16_t*")[0] == 0xDD86 then
      if ptr[labels["ETH.PRO"]] ~= 86 then
	 if ptr[labels["IPV6.NXT"]] == 0x73 then
	    print("got L2TPv3")
	    p.length = p.length - headersize
	    iovec.offset = iovec.offset + headersize
	    iovec.length = iovec.length - headersize
	    link.transmit(tx_decap, p)
	 else
	    packet.deref(p)
	    print("not L2TPv3", ptr[labels["IPV6.NXT"]])
	 end
      else
	 print("not IPv6", labels["ETH.PRO"], bit.tohex(ptr[labels["ETH.PRO"]]), bit.tohex(ffi.cast(ptr + labels["ETH.PRO"], "uint16_t*")[0]))
	 packet.deref(p)
      end
   end
end

function selftest ()
   -- Source -> NS -> L2TPv3 -> Tee -> L2TPv3 -> File
   --                            `-------------> File
   local c = config.new()
--   config.app(c, "Source", PcapReader, "apps/l2tpv3/input.cap")
   config.app(c, "Raw", RawSocket, "b")
   config.app(c, "NS", ns_responder, {--local_ip = "fc00::2",
				      local_ip = "\xFC\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02",
				      local_mac = "\x01\x01\x01\x01\x01\x01"})
--				      local_mac = "01:01:01:01:01:01"})
   config.app(c, "L2TPv3", L2TPv3,
	      {eth_dst = "02:02:02:02:02:02",
	       eth_src = "01:01:01:01:01:01",
	       session = "11 22 33 44",
	       cookie  = "11 22 33 44 55 66 77 88",
	       ipv6_src = "fc00::2",
	       ipv6_dst = "fc00::1"})
   config.app(c, "Tee", Tee)
   config.app(c, "FileEncap", PcapWriter, "apps/l2tpv3/encap.cap")
   config.app(c, "FileDecap", PcapWriter, "apps/l2tpv3/decap.cap")
--   config.link(c, "Source.output -> L2TPv3.decap")
--   config.link(c, "Source.output -> NS.south")
   config.link(c, "Raw.tx -> NS.south")
   config.link(c, "NS.north -> L2TPv3.decap")
--   config.link(c, "L2TPv3.encap -> FileEncap.input")
   config.link(c, "L2TPv3.encap -> Tee.input")
   config.link(c, "Tee.output1 -> L2TPv3.encap")
   config.link(c, "Tee.output2 -> FileEncap.input")
--   config.link(c, "L2TPv3.decap -> FileDecap.input")
   config.link(c, "L2TPv3.decap -> NS.north")
   config.link(c, "NS.south -> Raw.rx")
   engine.configure(c)
   engine.main({duration = 10})
   if (io.open("apps/l2tpv3/input.cap"):read("*a") ==
       io.open("apps/l2tpv3/decap.cap"):read("*a")) then
      print("selftest passed")
   else
      print("selftest failed")
      main.exit(1)
   end
end

