-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

io.stdout:setvbuf('no')
io.stderr:setvbuf('no')

local lib = require("core.lib")
local udp = require("lib.protocol.udp")
local ipv6 = require("lib.protocol.ipv6")
local eth = require("lib.protocol.ethernet")
local dg = require("lib.protocol.datagram")
local vhost = require("apps.vhost.vhost_user")
local esp = require("apps.ipsec.esp")
local filter = require("apps.packet_filter.pcap_filter")
local ffi = require("ffi")
local C = require("ffi").C

-- this is supposed to be run from a selftest shell script
-- which hopefully can figure out most arguments on its own.
if not (#main.parameters == 13 ) then
   print("need 13 arguments: srcmac dstmac srcip dstip srcport dstport spi txkey txsalt rxkey rxsalt seqno payload") -- XXX usage
   main.exit(1)
end

local args = {
   srcmac = main.parameters[1],
   dstmac = main.parameters[2],
   srcip = main.parameters[3],
   dstip = main.parameters[4],
   srcport = main.parameters[5],
   dstport = main.parameters[6],
   spi = main.parameters[7],
   txkey = main.parameters[8],
   txsalt = main.parameters[9],
   rxkey = main.parameters[10],
   rxsalt = main.parameters[11],
   seqno = main.parameters[12],
   payload = main.parameters[13],
}

local UDPing = {
   zone = "UDPing",
   config = {
      srcport = {default=args.srcport},
      dstport = {default=args.dstport},
      srcaddr = {default=args.srcip},
      dstaddr = {default=args.dstip},
      srclladdr = {default=args.srcmac},
      dstlladdr = {default=args.dstmac},
      payload = {default=args.payload}
   }
}

function UDPing:new (conf)
   local o = {
      conf = conf,
      ping = lib.throttle(1),
      timeout = lib.timeout(120)
   }
   return setmetatable(o, {__index = UDPing})
end

function UDPing:deudpify (p)
   local dgram = dg:new(p, eth)
   dgram:parse_n(3)
   return dgram
end

function UDPing:udpify (p)
   local dgram = dg:new(p)

   local udpcfg = {
      src_port = self.conf.srcport,
      dst_port = self.conf.dstport
   }
   local udpish = udp:new(udpcfg)

   local ipcfg = {
      src = ipv6:pton(self.conf.srcaddr),
      dst = ipv6:pton(self.conf.dstaddr),
      next_header = 17, -- UDP
      hop_limit = 64,
   }
   local ipish = ipv6:new(ipcfg)

   local ethcfg = {
      src = eth:pton(self.conf.srclladdr),
      dst = eth:pton(self.conf.dstlladdr),
      type = 0x86dd -- IPv6
   }
   local ethish = eth:new(ethcfg)

   local payload, length = dgram:payload()
   udpish:length(udpish:length() + length)
   udpish:checksum(payload, length, ipish)
   ipish:payload_length(udpish:length())

   dgram:push(udpish)
   dgram:push(ipish)
   dgram:push(ethish)

   return dgram:packet()
end

function UDPing:pull ()
   if self.ping() then
      link.transmit(self.output.output,
                    self:udpify(packet.from_string(self.conf.payload)))
   end
end

function UDPing:push ()
   if self.timeout() then error("No reply.") end

   while not link.empty(self.input.input) do
      local dgram = self:deudpify(link.receive(self.input.input))
      local recvstr = ffi.string(dgram:payload())
      print("< '" .. recvstr .. "'")
      assert(args.payload == recvstr,
             "wanted '"..(args.payload).."' got '"..recvstr.."'")
      packet.free(dgram:packet())
   end
end


local c = config.new()

config.app(c, "udping", UDPing)

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

local pcapconf = {
   filter = "ip6 and ip6 proto 50 " ..
      "and ether src "..args.dstmac.." " ..
      "and ether dst "..args.srcmac.." " ..
      "and ip6 src host "..args.dstip.." " ..
      "and ip6 dst host "..args.srcip
}
config.app(c, "filter", filter.PcapFilter, pcapconf)

config.link(c, "udping.output -> esp.decapsulated")
config.link(c, "esp.encapsulated -> vhost.rx")

config.link(c, "vhost.tx -> filter.input")
config.link(c, "filter.output -> esp.encapsulated")
config.link(c, "esp.decapsulated -> udping.input")

engine.configure(c)

local function received_pong ()
   return link.stats(engine.app_table.udping.input.input).rxpackets > 0
end
engine.main({done=received_pong})


