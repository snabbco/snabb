-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local udpify = require("apps.udpify.udpify")
local vhost = require("apps.vhost.vhost_user")
local esp = require("apps.ipsec.esp")
local null = require("apps.null.null")
local filter = require("apps.packet_filter.pcap_filter")
local ffi = require("ffi")

function run (parameters)
   -- this is supposed to be run from a selftest shell script
   -- which hopefully can figure out most arguments on its own.
   if not (#parameters == 13 ) then
      print("need 13 arguments: srcmac dstmac srcip dstip srcport dstport spi txkey txsalt rxkey rxsalt seqno payload") -- XXX usage
      main.exit(1)
   end

   local args = {
      srcmac = parameters[1],
      dstmac = parameters[2],
      srcip = parameters[3],
      dstip = parameters[4],
      srcport = parameters[5],
      dstport = parameters[6],
      spi = parameters[7],
      txkey = parameters[8],
      txsalt = parameters[9],
      rxkey = parameters[10],
      rxsalt = parameters[11],
      seqno = parameters[12],
      payload = parameters[13],
   }

   local c = config.new()

   local udpifyconf = {
      srcport = args.srcport,
      dstport = args.dstport,
      srcaddr = args.srcip,
      dstaddr = args.dstip,
      srclladdr = args.srcmac,
      dstlladdr = args.dstmac,
   }

   config.app(c, "udpify", udpify.UDPIfy, udpifyconf)

   local espconf = {
      spi = args.spi,
      transmit_key = args.txkey,
      transmit_salt =  args.txsalt,
      receive_key = args.rxkey,
      receive_salt =  args.rxsalt,
      receive_window = 32,
      resync_threshold = 8192,
      resync_attempts = 8,
      auditing = 1
   }

   config.app(c, "esp", esp.AES128gcm, espconf)

   local vhostconf = {
      socket_path = 'esp.sock',
      is_server = false
   }

   config.app(c, "vhost", vhost.VhostUser, vhostconf)
   config.app(c, "null", null.Nullapp, {})

   local pcapconf = {
      filter = "ip6 and ip6 proto 50 " ..
           "and ether src "..args.dstmac.." " ..
           "and ether dst "..args.srcmac.." " ..
           "and ip6 src host "..args.dstip.." " ..
           "and ip6 dst host "..args.srcip
   }
   config.app(c, "filter", filter.PcapFilter, pcapconf)

   config.link(c, "udpify.packetfeed -> esp.decapsulated")
   config.link(c, "esp.encapsulated -> vhost.rx")

   config.link(c, "vhost.tx -> filter.input")
   config.link(c, "filter.output -> esp.encapsulated")
   config.link(c, "esp.decapsulated -> udpify.packetfeed")

   engine.configure(c)
   local link_in, link_out = link.new("test_in"), link.new("test_out")
   engine.app_table.udpify.input.rawfeed = link_out
   engine.app_table.udpify.output.rawfeed = link_in

   engine.app_table.esp.encrypt.seq.no = tonumber(args.seqno);

   local p = packet.from_string(args.payload)
   print("> '" .. ffi.string(p.data, p.length) .. "'")
   local timeout = 0
   while timeout < 120 do
	   local px = packet.clone(p);
	   link.transmit(link_out, px)
	   engine.main({duration=1, report = {showlinks=false}})
		timeout = timeout + 1
		if link.nreadable(link_in) >= 1 then
			break
		end
   end
   if link.nreadable(link_in) >= 1 then
      local q = link.receive(link_in)
      local recvstr = ffi.string(q.data, q.length)
      print("< '" .. recvstr .. "'")
      assert(args.payload == recvstr,
         "wanted '"..(args.payload).."' got '"..recvstr.."'")
   else
      assert(false, "No reply whatsoever")
   end
end
