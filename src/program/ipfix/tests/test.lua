-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

-- A regression test for 'snabb ipfix probe'

local ipfix_probe = require("program.ipfix.probe.probe")
local config_rpc = require("program.config.common")
local worker = require("core.worker")
local lib = require("core.lib")


function get_state (pid, path)
   local opts = { command='get-state', with_path=true, is_config=false }
   local args = config_rpc.parse_command_line({tostring(pid), path}, opts)
   if args.error then
      return args
   end
   local response = config_rpc.call_leader(
      args.instance_id, 'get-state',
      { schema = args.schema_name, revision = args.revision_date,
        path = args.path, print_default = args.print_default,
        format = args.format })
   return response
end

function print_state (pid, path)
   local r = get_state(pid, path)
   if r.error then
      error(r.error)
   else
      print(r.state)
   end
end

function get_counter (pid, path)
   local r = get_state(pid, path)
   if r.error then
      error(r.error)
   else
      return tonumber(r.state)
   end
end

-- Selftest

function selftest ()
   local pcap = "program/ipfix/tests/sanitized500k_truncated128.pcap"
   local confpath = "program/ipfix/tests/test_v4_v6_dnshttp.conf"

   -- Maybe decompress pcap
   if not io.open(pcap) then
      local cmd = "bunzip2 -k "..pcap..".bz2" 
      print(cmd)
      os.execute(cmd)
   end

   local probe_pid = worker.start('ipfix_probe',
      ([[require("program.ipfix.probe.probe").run{
         "-T", %q, %q
      }]]):format(pcap, confpath))

   local ip4_flows = "/snabbflow-state/exporter[name=ip]/template[id=1256]/flows-exported"
   local ip6_flows = "/snabbflow-state/exporter[name=ip]/template[id=1512]/flows-exported"
   local http4_flows = "/snabbflow-state/exporter[name=dnshttp]/template[id=257]/flows-exported"
   local dns4_flows = "/snabbflow-state/exporter[name=dnshttp]/template[id=258]/flows-exported"
   local http6_flows = "/snabbflow-state/exporter[name=dnshttp]/template[id=513]/flows-exported"
   local dns6_flows = "/snabbflow-state/exporter[name=dnshttp]/template[id=514]/flows-exported"


   local prev_ip4_flows = 0
   local function complete ()
      local ok, ret = pcall(function ()
         return get_counter(probe_pid, ip4_flows)
      end)
      if not ok then
         return false
      end
      if prev_ip4_flows > 0 and prev_ip4_flows == ret then
         return true
      else
         prev_ip4_flows = ret
         return false
      end
   end

   lib.waitfor2("exported flows", complete, 60, 2*1000000) -- 2s interval

   print("/snabbflow-state/exporter:")
   print_state(probe_pid, "/snabbflow-state/exporter")

   local function expect (counter, expected, tolerance)
      print(counter)
      print("expected:", expected, "+/-", math.floor(expected*tolerance))
      local actual = get_counter(probe_pid, counter)
      print("actual:", actual)
      local diff = math.abs(1-actual/expected)
      assert(diff <= tolerance, "Flows mismatch!")
   end

   expect(ip4_flows, 30000, 0.2)
   expect(ip6_flows, 1400, 0.1)
   expect(http4_flows, 200, 0.2)
   expect(dns4_flows, 1300, 0.2)
   expect(http6_flows, 10, 0.3)
   expect(dns6_flows, 700, 0.2)


   worker.stop('ipfix_probe')
end
