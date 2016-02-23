#!/usr/bin/env luajit
-- -*- lua -*-
module(..., package.seeall)
package.path = package.path .. ";../?.lua;../../src/?.lua"
-- Compare the results of the libpcap/bpf and pure-lua pflua pipelines.

local pf = require("pf")
local savefile = require("pf.savefile")
local utils = require('pf.utils')

local pflang = require('pfquickcheck.pflang')

function property(packets)
   --nil pkt_idx, pflang_expr, bpf_result, pflua_result to avoid
   -- confusing debug information
   pkt_idx, pflang_expr, bpf_result, pflua_result = nil
   local pkt, P, pkt_len, libpcap_pred, pflua_pred
   a = pflang.Pflang()
   pflang_expr = table.concat(a, ' ')
   pkt, pkt_idx = utils.choose_with_index(packets)
   P, pkt_len = pkt.packet, pkt.len
   libpcap_pred = pf.compile_filter(pflang_expr, { bpf = true })
   pflua_pred = pf.compile_filter(pflang_expr)
   bpf_result = libpcap_pred(P, pkt_len)
   pflua_result = pflua_pred(P, pkt_len)
   return bpf_result, pflua_result
end

function print_extra_information()
   print(("The pflang expression was %s and the packet number %s"):
         format(pflang_expr, pkt_idx))
   print(("BPF: %s, pure-lua: %s"):format(bpf_result, pflua_result))
end

function handle_prop_args(prop_args)
   if #prop_args ~= 1 then
      print("Usage: (pflua-quickcheck [args] properties/pflua_pipelines_match)"
            .. " PATH/TO/CAPTURE.PCAP")
      os.exit(1)
   end

   local capture = prop_args[1]
   return savefile.load_packets(capture)
end

