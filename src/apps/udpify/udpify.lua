-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- This app implements a point-to-point encryption tunnel using ESP with
-- AES-128-GCM.

module(..., package.seeall)
local ffi = require("ffi")
local lib = require("core.lib")
local udp = require("lib.protocol.udp")
local ipv6 = require("lib.protocol.ipv6")
local eth = require("lib.protocol.ethernet")
local dg = require("lib.protocol.datagram")
local C = require("ffi").C

UDPIfy = {
   config = {
      srcaddr = {required=true},
      dstaddr = {required=true},
      srcport =  {required=true},
      dstport = {required=true},
      srclladdr = {required=true},
      dstlladdr = {required=true},
   }
}

function UDPIfy:new (conf)
   local self = {}
   self.conf = conf;
   return setmetatable(self, {__index = UDPIfy})
end

function UDPIfy:deudpify(p)
   local dgram = dg:new(p, eth)
   dgram:parse_n(3)
   local eth, ipv6, udp = unpack(dgram:stack())
   local result = ffi.string(dgram:payload())
   return result
end

function UDPIfy:udpify(p)

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
   local ethish = eth:new(ethcfg);

   local payload, length = dgram:payload()
   udpish:length(udpish:length() + length);
   udpish:checksum(payload, length, ipish);
   ipish:payload_length(udpish:length())

   dgram:push(udpish);
   dgram:push(ipish);
   dgram:push(ethish);

   return dgram:packet()
end

function UDPIfy:pull ()
   local input = self.input.rawfeed
   local output = self.output.packetfeed
   for _=1,link.nreadable(input) do
      --print("udpify: pull 1!");
      local p = self:udpify(link.receive(input))
      link.transmit(output, p)
   end

   local input = self.input.packetfeed
   local output = self.output.rawfeed
   for _=1,link.nreadable(input) do
      --print("udpify: pull 2!");
      local p = link.receive(input)
      local q = self:deudpify(p)
      packet.free(p)
      if q then
         link.transmit(output, packet.from_string(q))
      else
         packet.free(p)
      end
   end
end
