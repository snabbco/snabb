module(..., package.seeall)

local binding_table = require("apps.lwaftr.binding_table")
local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local stream = require("apps.lwaftr.stream")

local CONF_FILE_DUMP = "/tmp/lwaftr-%d.conf"
local BINDING_TABLE_FILE_DUMP = "/tmp/binding-table-%d.txt"

Dumper = {}

function Dumper.mac (val)
   return ethernet:ntop(val)
end

function Dumper.ipv4 (val)
   return ipv4:ntop(val)
end

function Dumper.ipv6 (val)
   return ipv6:ntop(val)
end

function Dumper.number (val)
   assert(tonumber(val), "Not a number")
   return tostring(val)
end

function Dumper.string (val)
   assert(tostring(val), "Not a string")
   return val
end

function Dumper.boolean (val)
   assert(type(val) == "boolean", "Not a boolean")
   return val and "true" or "false"
end

function Dumper.icmp_policy (val)
   if val == 1 then return "DROP" end
   if val == 2 then return "ALLOW" end
end

local lwaftr_conf_spec = {
   aftr_ipv4_ip=Dumper.ipv4,
   aftr_ipv6_ip=Dumper.ipv6,
   aftr_mac_b4_side=Dumper.mac,
   aftr_mac_inet_side=Dumper.mac,
   next_hop6_mac=Dumper.mac,
   binding_table=Dumper.string,
   hairpinning=Dumper.boolean,
   icmpv4_rate_limiter_n_packets=Dumper.number,
   icmpv4_rate_limiter_n_seconds=Dumper.number,
   icmpv6_rate_limiter_n_packets=Dumper.number,
   icmpv6_rate_limiter_n_seconds=Dumper.number,
   inet_mac=Dumper.mac,
   ipv4_mtu=Dumper.number,
   ipv6_mtu=Dumper.number,
   max_fragments_per_reassembly_packet=Dumper.number,
   max_ipv4_reassembly_packets=Dumper.number,
   max_ipv6_reassembly_packets=Dumper.number,
   next_hop_ipv4_addr=Dumper.ipv4,
   next_hop_ipv6_addr=Dumper.ipv6,
   policy_icmpv4_incoming=Dumper.icmp_policy,
   policy_icmpv4_outgoing=Dumper.icmp_policy,
   policy_icmpv6_incoming=Dumper.icmp_policy,
   policy_icmpv6_outgoing=Dumper.icmp_policy,
   v4_vlan_tag=Dumper.number,
   v6_vlan_tag=Dumper.number,
   vlan_tagging=Dumper.boolean,
   ipv4_ingress_filter=Dumper.string,
   ipv4_egress_filter=Dumper.string,
   ipv6_ingress_filter=Dumper.string,
   ipv6_egress_filter=Dumper.string,
}

local function do_dump_configuration (conf)
   local result = {}
   for k,v in pairs(conf) do
      local fn = lwaftr_conf_spec[k]
      if fn then
         table.insert(result, ("%s = %s"):format(k, fn(v)))
      end
   end
   table.sort(result)
   return table.concat(result, "\n")
end

local function write_to_file(filename, content)
   local fd = assert(io.open(filename, "wt"),
      ("Couldn't open file: '%s'"):format(filename))
   fd:write(content)
   fd:close()
end

function dump_configuration(lwstate)
   local dest = (CONF_FILE_DUMP):format(os.time())
   print(("Dump lwAFTR configuration: '%s'"):format(dest))
   write_to_file(dest, do_dump_configuration(lwstate.conf))
end

local function bt_is_fresh (bt_txt, bt_o)
   local source = stream.open_input_byte_stream(bt_txt)
   local compiled_stream = binding_table.maybe(stream.open_input_byte_stream, bt_o)
   return compiled_stream and
      binding_table.has_magic(compiled_stream) and
      binding_table.is_fresh(compiled_stream, source.mtime_sec, source.mtime_nsec)
end

local function copy_file (dest, src)
   local fin = assert(io.open(src, "rt"),
      ("Couldn't open file: '%s'"):format(src))
   local fout = assert(io.open(dest, "wt"),
      ("Couldn't open file: '%s'"):format(dest))
   while true do
      local str = fin:read(4096)
      if not str then break end
      fout:write(str)
   end
   fin:close()
   fout:close()
end

function dump_binding_table (lwstate)
   print("Dumping lwAFTR binding table...")
   lwstate.binding_table:dump(BINDING_TABLE_FILE_DUMP:format(os.time()))
end

function selftest ()
   print("selftest: dump")
   local lwconf = require("apps.lwaftr.conf")
   local policies = lwconf.policies
   local equal = require('core.lib').equal
   local function string_file(str)
      local pos = 1
      return {
         read = function(self, n)
            assert(n==1)
            local ret
            if pos <= #str then
               ret = str:sub(pos,pos)
               pos = pos + 1
            end
            return ret
         end,
         close = function(self) str = nil end
      }
   end
   local function remove_leading_spaces(str)
      local lines = {}
      for line in str:gmatch("([^\n]+)") do
         line = line:gsub("^%s+", "")
         if #line > 0 then
            table.insert(lines, line)
         end
      end
      return table.concat(lines, "\n")
   end
   local function test(conf, expected)
      local conf_table = lwconf.load_lwaftr_config(string_file(conf))
      conf = do_dump_configuration(conf_table)
      expected = remove_leading_spaces(expected)
      if not equal(conf, expected) then
         error("lwAFTR's configuration and dumped version don't match")
      end
   end
   test([[
         aftr_ipv4_ip=1.2.3.4
         aftr_ipv6_ip=8:9:a:b:c:d:e:f
         aftr_mac_b4_side=22:22:22:22:22:22
         aftr_mac_inet_side=12:12:12:12:12:12
         next_hop6_mac=44:44:44:44:44:44
         binding_table="foo-table.txt"
         hairpinning=false
         icmpv4_rate_limiter_n_packets=6e3
         icmpv4_rate_limiter_n_seconds=2
         icmpv6_rate_limiter_n_packets=6e3
         icmpv6_rate_limiter_n_seconds=2
         inet_mac = 68:68:68:68:68:68
         ipv4_mtu = 1460
         ipv6_mtu = 1500
         max_fragments_per_reassembly_packet = 40
         max_ipv4_reassembly_packets = 5
         max_ipv6_reassembly_packets = 10
         policy_icmpv4_incoming = ALLOW
         policy_icmpv6_incoming = ALLOW
         policy_icmpv4_outgoing = ALLOW
         policy_icmpv6_outgoing = ALLOW
         v4_vlan_tag = 1092 # 0x444
         v6_vlan_tag = 1638 # 0x666
         vlan_tagging = true
         ipv4_ingress_filter="ip"
         ipv4_egress_filter="ip"
         ipv6_ingress_filter="ip6"
         ipv6_egress_filter="ip6"
   ]], [[
         aftr_ipv4_ip = 1.2.3.4
         aftr_ipv6_ip = 8:9:a:b:c:d:e:f
         aftr_mac_b4_side = 22:22:22:22:22:22
         aftr_mac_inet_side = 12:12:12:12:12:12
         binding_table = foo-table.txt
         hairpinning = false
         icmpv4_rate_limiter_n_packets = 6000
         icmpv4_rate_limiter_n_seconds = 2
         icmpv6_rate_limiter_n_packets = 6000
         icmpv6_rate_limiter_n_seconds = 2
         inet_mac = 68:68:68:68:68:68
         ipv4_egress_filter = ip
         ipv4_ingress_filter = ip
         ipv4_mtu = 1460
         ipv6_egress_filter = ip6
         ipv6_ingress_filter = ip6
         ipv6_mtu = 1500
         max_fragments_per_reassembly_packet = 40
         max_ipv4_reassembly_packets = 5
         max_ipv6_reassembly_packets = 10
         next_hop6_mac = 44:44:44:44:44:44
         policy_icmpv4_incoming = ALLOW
         policy_icmpv4_outgoing = ALLOW
         policy_icmpv6_incoming = ALLOW
         policy_icmpv6_outgoing = ALLOW
         v4_vlan_tag = 1092
         v6_vlan_tag = 1638
         vlan_tagging = true
   ]])
   print("ok")
end
