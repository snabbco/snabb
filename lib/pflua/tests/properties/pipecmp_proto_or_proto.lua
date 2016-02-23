#!/usr/bin/env luajit
-- -*- lua -*-
module(..., package.seeall)
package.path = package.path .. ";../?.lua;../../src/?.lua"
local pf = require("pf")
local savefile = require("pf.savefile")
local utils = require('pf.utils')

local function choose_proto()
    local protos = {"icmp", "igmp", "igrp", "pim", "ah", "esp", "vrrp",
                     "udp", "tcp", "sctp", "ip", "arp", "rarp", "ip6"}
    return utils.choose(protos)
end

function property(packets)
   local expr = {choose_proto(), 'or', choose_proto()}
   or_expr = table.concat(expr, ' ') -- Intentionally not local

   local pkt, pkt_idx = utils.choose_with_index(packets)
   local P, pkt_len = pkt.packet, pkt.len

   local libpcap_pred = pf.compile_filter(or_expr, { bpf = true })
   local pflua_pred = pf.compile_filter(or_expr)
   local bpf_result = libpcap_pred(P, pkt_len)
   local pflua_result = pflua_pred(P, pkt_len) 

   return bpf_result, pflua_result
end

function print_extra_information()
   print(("The arithmetic expression was %s"):format(or_expr))
end

function handle_prop_args(prop_args)
   if #prop_args < 1 or #prop_args > 2 then
      print("Usage: (pflua-quickcheck [args] " ..
            "properties/pipecmp_proto_or_proto) PATH/TO/CAPTURE.PCAP")
      os.exit(1)
   end

   local capture, filter_list = prop_args[1], prop_args[2]
   local packets = savefile.load_packets(capture)
   local filters
   if filter_list then
      filters = load_filters(filter_list)
   end
   return packets, filter_list
end
