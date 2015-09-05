--[[
--
-- This module is used to obtain the resulting jitted asm code for a pcap
-- expression using pflua.
--
-- The file used for packet filtering is a 1GB file from pflua-bench, so it's
-- necessary to clone that repo, uncompress the file and create a symbolic link:
--
--  $ git clone https://github.com/Igalia/pflua-bench.git
--  $ pflua-bench=<path-to-pflua-bench>
--  $ pflua=<path-to-pflua>
--  $ unxz $pflua-bench/savefiles/one-gigabyte.pcap.xz
--  $ ln -fs $pflua-bench/savefiles/one-gigabyte.pcap \
--      $pflua/tests/data/one-gigabyte.pcap
--
--]]

module("pflua_asm", package.seeall)

package.path = package.path .. ";../../src/?.lua"

local savefile = require("pf.savefile")
local libpcap = require("pf.libpcap")
local pf = require("pf")

-- Counts number of packets within file
function filter_count(pred, file)
   local total_pkt = 0
   local count = 0
   local records = savefile.records_mm(file)

   while true do
      local pkt, hdr = records()
      if not pkt then break end

      local length = hdr.incl_len
      execute_pred_ensuring_trace(pred, pkt, length)
   end
   return count, total_pkt
end

-- Executing pred within a function ensures a trace for this call
function execute_pred_ensuring_trace(pred, packet, length)
    pred(packet, length)
end

-- Calls func() during seconds
function call_during_seconds(seconds, func, pred, file)
    local time = os.time
    local finish = time() + seconds
    while (true) do
        func(pred, file)
        if (time() > finish) then break end
    end
end

function selftest(filter)
   print("selftest: pflua_asm")

   local file = "../tests/data/one-gigabyte.pcap"
   if (filter == nil or filter == '') then
      filter = "tcp port 80"
   end

   local pred = pf.compile_filter(filter, {dlt="EN10MB"})
   call_during_seconds(1, filter_count, pred, file)

   print("OK")
end
