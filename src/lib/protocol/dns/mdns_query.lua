-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local datagram = require("lib.protocol.datagram")
local dns = require("lib.protocol.dns.dns")
local ethernet = require("lib.protocol.ethernet")
local ffi = require("ffi")
local ipv4 = require("lib.protocol.ipv4")
local lib = require("core.lib")
local mdns = require("lib.protocol.dns.mdns")
local udp = require("lib.protocol.udp")

local MDNS = mdns.MDNS

local query_record = dns.query_record

local htons, ntohs = lib.htons, lib.ntohs

local ETHER_PROTO_IPV4 = 0x0800
local STANDARD_QUERY = 0x0
local UDP_PROTOCOL = 0x11

mDNSQuery = {}

function mDNSQuery.new (args)
   local o = {
      src_eth = assert(args.src_eth),
      src_ipv4 = assert(args.src_ipv4),
   }
   return setmetatable(o, {__index=mDNSQuery})
end

function mDNSQuery:build (...)
   local queries = assert({...})
   local dgram = datagram:new()
   local ether_h = ethernet:new({dst = ethernet:pton(mdns.DST_ETHER),
                                 src = ethernet:pton(self.src_eth),
                                 type = ETHER_PROTO_IPV4})
   local ipv4_h = ipv4:new({dst = ipv4:pton(mdns.DST_IPV4),
                            src = ipv4:pton(self.src_ipv4),
                            protocol = UDP_PROTOCOL,
                            ttl = 255,
                            flags = 0x02})
   local udp_h = udp:new({src_port = 5353,
                          dst_port = mdns.DST_PORT})
   -- Add payload.
   local payload, len = mDNSQuery:payload(queries)
   -- Calculate checksums.
   udp_h:length(udp_h:sizeof() + len)
   udp_h:checksum(payload, len, ipv4_h)
   ipv4_h:total_length(ipv4_h:sizeof() + udp_h:sizeof() + len)
   ipv4_h:checksum()
   -- Generate packet.
   dgram:payload(payload, len)
   dgram:push(udp_h)
   dgram:push(ipv4_h)
   dgram:push(ether_h)
   return dgram:packet()
end

function mDNSQuery:payload (queries)
   local function w16 (buffer, val)
      ffi.cast("uint16_t*", buffer)[0] = val
   end
   local function serialize (rr)
      local ret = ffi.new("uint8_t[?]", rr:sizeof())
      local length = rr:sizeof() - 4
      local h = rr:header()
      ffi.copy(ret, h.name, length)
      w16(ret + length, h.type)
      w16(ret + length + 2, h.class)
      return ret, rr:sizeof()
   end
   local dgram = datagram:new()
   local mdns_header = MDNS:new({
      id = 0,
      flags = STANDARD_QUERY,
      questions = #queries,
      answer_rrs = 0,
      authority_rrs = 0,
      additional_rrs = 0,
   })
   local t = {}
   for _, each in ipairs(queries) do
      local rr = query_record:new({
         name = each,
         type = dns.PTR,
         class = dns.CLASS_IN,
      })
      -- TODO: dgram:push doesn't work. I think is due to the variable-length
      -- nature of the header.
      local data, len = serialize(rr)
      dgram:push_raw(data, len)
   end
   dgram:push(mdns_header)
   local pkt = dgram:packet()
   return pkt.data, pkt.length
end

function selftest()
   local mdns_query = mDNSQuery.new({
      src_eth = "ce:6c:59:f2:f3:c1",
      src_ipv4 = "192.168.0.1",
   })
   local query = "_services._dns-sd._udp.local"
   local pkt = assert(mdns_query:build(query))
   assert(pkt.length == 88)
end
