module("pf",package.seeall)

local savefile = require("pf.savefile")
local types = require("pf.types")
local libpcap = require("pf.libpcap")
local bpf = require("pf.bpf")
local parse = require('pf.parse')
local expand = require('pf.expand')
local optimize = require('pf.optimize')
local anf = require('pf.anf')
local ssa = require('pf.ssa')
local backend = require('pf.backend')
local utils = require('pf.utils')

-- TODO: rename the 'libpcap' option to reduce terminology overload
local compile_defaults = {
   optimize=true, libpcap=false, bpf=false, source=false
}
function compile_filter(filter_str, opts)
   local opts = utils.parse_opts(opts or {}, compile_defaults)
   local dlt = opts.dlt or "EN10MB"
   if opts.libpcap then
      local bytecode = libpcap.compile(filter_str, dlt, opts.optimize)
      if opts.source then return bpf.disassemble(bytecode) end
      local header = types.pcap_pkthdr(0, 0, 0, 0)
      return function(P, len)
         header.incl_len = len
         header.orig_len = len
         return libpcap.offline_filter(bytecode, header, P) ~= 0
      end
   elseif opts.bpf then
      local bytecode = libpcap.compile(filter_str, dlt, opts.optimize)
      if opts.source then return bpf.compile_lua(bytecode) end
      return bpf.compile(bytecode)
   else -- pflua
      local expr = parse.parse(filter_str)
      expr = expand.expand(expr, dlt)
      if opts.optimize then expr = optimize.optimize(expr) end
      expr = anf.convert_anf(expr)
      expr = ssa.convert_ssa(expr)
      if opts.source then return backend.emit_lua(expr) end
      return backend.emit_and_load(expr, filter_str)
   end
end

function selftest ()
   print("selftest: pf")
   
   local function test_null(str)
      local f1 = compile_filter(str, { libpcap = true })
      local f2 = compile_filter(str, { bpf = true })
      local f3 = compile_filter(str, {})
      assert(f1(str, 0) == false, "null packet should be rejected (libpcap)")
      assert(f2(str, 0) == false, "null packet should be rejected (bpf)")
      assert(f3(str, 0) == false, "null packet should be rejected (pflua)")
   end
   test_null("icmp")
   test_null("tcp port 80 and (((ip[2:2] - ((ip[0]&0xf)<<2)) - ((tcp[12]&0xf0)>>2)) != 0)")

   local function assert_count(filter, packets, expected)
      function count_matched(pred)
         local matched = 0
         for i=1,#packets do
            if pred(packets[i].packet, packets[i].len) then
               matched = matched + 1
            end
         end
         return matched
      end

      local f1 = compile_filter(filter, { libpcap = true })
      local f2 = compile_filter(filter, { bpf = true })
      local f3 = compile_filter(filter, {})
      local actual
      actual = count_matched(f1)
      assert(actual == expected,
             'libpcap: got ' .. actual .. ', expected ' .. expected)
      actual = count_matched(f2)
      assert(actual == expected,
             'bpf: got ' .. actual .. ', expected ' .. expected)
      actual = count_matched(f3)
      assert(actual == expected,
             'pflua: got ' .. actual .. ', expected ' .. expected)
   end
   local v4 = savefile.load_packets("../tests/data/v4.pcap")
   assert_count('', v4, 43)
   assert_count('ip', v4, 43)
   assert_count('tcp', v4, 41)
   assert_count('tcp port 80', v4, 41)

   print("OK")
end
