#!/usr/bin/env luajit
-- -*- lua -*-
module(..., package.seeall)
package.path = package.path .. ";../?.lua;../../src/?.lua"

local ffi = require("ffi")
local parse = require("pf.parse")
local savefile = require("pf.savefile")
local expand = require("pf.expand")
local optimize = require("pf.optimize")
local codegen = require('pf.backend')
local utils = require('pf.utils')
local pp = utils.pp

local pflua_ir = require('pfquickcheck.pflua_ir')
local pfcompile = require('pfquickcheck.pfcompile')

local function load_filters(file)
   local ret = {}
   for line in io.lines(file) do table.insert(ret, line) end
   return ret
end

-- Several variables are non-local for print_extra_information()
function property(packets, filter_list)
   local packet
   -- Reset these every run, to minimize confusing output on crashes
   optimized_pred, unoptimized_pred, expanded, optimized = nil, nil, nil, nil
   packet, packet_idx = utils.choose_with_index(packets)
   P, packet_len = packet.packet, packet.len
   local F
   if filters then
      F = utils.choose(filters)
      expanded = expand.expand(parse.parse(F), "EN10MB")
   else
      F = "generated expression"
      expanded = pflua_ir.Logical()
   end
   optimized = optimize.optimize(expanded)

   unoptimized_pred = pfcompile.compile_ast(expanded, F)
   optimized_pred = pfcompile.compile_ast(optimized, F)
   return unoptimized_pred(P, packet_len), optimized_pred(P, packet_len)
end

-- The test harness calls this on property failure.
function print_extra_information()
   if expanded then
      print("--- Expanded:")
      pp(expanded)
   else return -- Nothing else useful available to print
   end
   if optimized then
      print("--- Optimized:")
      pp(optimized)
   else return -- Nothing else useful available to print
   end

   print(("On packet %s: unoptimized was %s, optimized was %s"):
         format(packet_idx,
                unoptimized_pred(P, packet_len),
                optimized_pred(P, packet_len)))
end

function handle_prop_args(prop_args)
   if #prop_args < 1 or #prop_args > 2 then
      print("Usage: (pflua-quickcheck [args] properties/opt_eq_unopt) " ..
            "PATH/TO/CAPTURE.PCAP [FILTER-LIST]")
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
