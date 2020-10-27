-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local DNS = require("lib.protocol.dns.dns").DNS
local ethernet = require("lib.protocol.ethernet")
local ffi = require("ffi")
local header = require("lib.protocol.header")
local ipv4 = require("lib.protocol.ipv4")
local lib = require("core.lib")
local udp = require("lib.protocol.udp")

local htons, ntohs = lib.htons, lib.ntohs

DST_ETHER = "01:00:5e:00:00:fb"
DST_IPV4 = "224.0.0.251"
DST_PORT = 5353

local STANDARD_QUERY_RESPONSE = 0x8400

local ethernet_header_size = 14
local ipv4_header_size = 20
local udp_header_size = 8

MDNS = subClass(header)
MDNS._name = "mdns"
MDNS:init({
   [1] = ffi.typeof[[
   struct {
      uint16_t id;
      uint16_t flags;
      uint16_t questions;
      uint16_t answer_rrs;
      uint16_t authority_rrs;
      uint16_t additional_rrs;
   } __attribute__((packed))
   ]]
})

function MDNS:new (config)
   local o = MDNS:superClass().new(self)
   o:id(config.id)
   o:flags(config.flags)
   o:questions(config.questions)
   o:answer_rrs(config.answer_rrs)
   o:authority_rrs(config.authority_rrs)
   o:additional_rrs(config.additional_rrs)
   return o
end

function MDNS:id (id)
   if id then
      self:header().id = htons(id)
   end
   return ntohs(self:header().id)
end

function MDNS:flags (flags)
   if flags then
      self:header().flags = htons(flags)
   end
   return ntohs(self:header().flags)
end

function MDNS:questions (questions)
   if questions then
      self:header().questions = htons(questions)
   end
   return ntohs(self:header().questions)
end

function MDNS:answer_rrs (answer_rrs)
   if answer_rrs then
      self:header().answer_rrs = htons(answer_rrs)
   end
   return ntohs(self:header().answer_rrs)
end

function MDNS:authority_rrs (authority_rrs)
   if authority_rrs then
      self:header().authority_rrs = htons(authority_rrs)
   end
   return ntohs(self:header().authority_rrs)
end

function MDNS:additional_rrs (additional_rrs)
   if additional_rrs then
      self:header().additional_rrs = htons(additional_rrs)
   end
   return ntohs(self:header().additional_rrs)
end

function MDNS.is_mdns (pkt)
   local ether_hdr = ethernet:new_from_mem(pkt.data, ethernet_header_size)
   local ipv4_hdr = ipv4:new_from_mem(pkt.data + ethernet_header_size, ipv4_header_size)
   local udp_hdr = udp:new_from_mem(pkt.data + ethernet_header_size + ipv4_header_size, udp_header_size)

   return ethernet:ntop(ether_hdr:dst()) == DST_ETHER and
      ipv4:ntop(ipv4_hdr:dst()) == DST_IPV4 and
      udp_hdr:dst_port() == DST_PORT
end

local function mdns_payload (pkt)
   local payload_offset = ethernet_header_size + ipv4_header_size + udp_header_size
   return pkt.data + payload_offset, pkt.length - payload_offset
end

function MDNS.is_response (pkt)
   local payload = mdns_payload(pkt)
   local mdns = MDNS:new_from_mem(payload, MDNS:sizeof())
   return mdns:flags() == STANDARD_QUERY_RESPONSE
end

function MDNS.parse_packet (pkt)
   assert(MDNS.is_mdns(pkt))
   local ret = {
      questions = {},
      answer_rrs = {},
      authority_rrs = {},
      additional_rrs = {},
   }
   local payload, length = mdns_payload(pkt)
   local mdns_hdr = MDNS:new_from_mem(payload, MDNS:sizeof())
   -- Skip header.
   payload, length = payload + MDNS:sizeof(), length - MDNS:sizeof()
   local function collect_records (n)
      local t = {}
      local rrs, rrs_len = DNS.parse_records(payload, length, n)
      for _, each in ipairs(rrs) do table.insert(t, each) end
      payload = payload + rrs_len
      length = length - rrs_len
      return t
   end
   ret.questions = collect_records(mdns_hdr:questions())
   ret.answer_rrs = collect_records(mdns_hdr:answer_rrs())
   ret.authority_rrs = collect_records(mdns_hdr:authority_rrs())
   ret.additional_rrs = collect_records(mdns_hdr:additional_rrs())
   return ret
end

function selftest()
   local function parse_response ()
      -- MDNS response.
      local pkt = packet.from_string(lib.hexundump ([[
         01:00:5e:00:00:fb ce:6c:59:f2:f3:c1 08 00 45 00
         01 80 00 00 40 00 ff 11 82 88 c0 a8 56 40 e0 00
         00 fb 14 e9 14 e9 01 6c d2 12 00 00 84 00 00 00
         00 01 00 00 00 03 0b 5f 67 6f 6f 67 6c 65 63 61
         73 74 04 5f 74 63 70 05 6c 6f 63 61 6c 00 00 0c
         00 01 00 00 00 78 00 2e 2b 43 68 72 6f 6d 65 63
         61 73 74 2d 38 34 38 64 61 35 39 64 38 63 62 36
         34 35 39 61 39 39 37 31 34 33 34 62 31 64 35 38
         38 62 61 65 c0 0c c0 2e 00 10 80 01 00 00 11 94
         00 b3 23 69 64 3d 38 34 38 64 61 35 39 64 38 63
         62 36 34 35 39 61 39 39 37 31 34 33 34 62 31 64
         35 38 38 62 61 65 23 63 64 3d 37 32 39 32 37 38
         45 30 32 35 46 43 46 44 34 44 43 44 43 37 46 42
         39 45 38 42 43 39 39 35 42 37 13 72 6d 3d 39 45
         41 37 31 43 38 33 43 43 45 46 37 39 32 37 05 76
         65 3d 30 35 0d 6d 64 3d 43 68 72 6f 6d 65 63 61
         73 74 12 69 63 3d 2f 73 65 74 75 70 2f 69 63 6f
         6e 2e 70 6e 67 09 66 6e 3d 4b 69 62 62 6c 65 07
         63 61 3d 34 31 30 31 04 73 74 3d 30 0f 62 73 3d
         46 41 38 46 43 41 39 33 42 35 43 34 04 6e 66 3d
         31 03 72 73 3d c0 2e 00 21 80 01 00 00 00 78 00
         2d 00 00 00 00 1f 49 24 38 34 38 64 61 35 39 64
         2d 38 63 62 36 2d 34 35 39 61 2d 39 39 37 31 2d
         34 33 34 62 31 64 35 38 38 62 61 65 c0 1d c1 2d
         00 01 80 01 00 00 00 78 00 04 c0 a8 56 40
      ]], 398))
      local response = MDNS.parse_packet(pkt)
      assert(#response.answer_rrs == 1)
      assert(#response.additional_rrs == 3)
   end
   local function parse_request ()
      local mDNSQuery = require("lib.protocol.dns.mdns_query").mDNSQuery
      local requester = mDNSQuery.new({
         src_eth = "ce:6c:59:f2:f3:c1",
         src_ipv4 = "192.168.0.1",
      })
      local query = "_services._dns-sd._udp.local"
      local request = MDNS.parse_packet(requester:build(query))
      assert(#request.questions == 1)
   end
   parse_response()
   parse_request()
end
