module(..., package.seeall)

local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local binding_table = require("apps.lwaftr.binding_table")
local stream = require("apps.lwaftr.stream")

local CONF_FILE_DUMP = "/tmp/lwaftr-%s.conf"
local BINDING_TABLE_FILE_DUMP = "/tmp/binding-%s.table"

-- 'ip' is in host bit order, convert to network bit order
local function ipv4number_to_str(ip)
   local a = bit.band(ip, 0xff)
   local b = bit.band(bit.rshift(ip, 8), 0xff)
   local c = bit.band(bit.rshift(ip, 16), 0xff)
   local d = bit.rshift(ip, 24)
   return ("%d.%d.%d.%d"):format(a, b, c, d)
end

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
   icmpv6_rate_limiter_n_packets=Dumper.number,
   icmpv6_rate_limiter_n_seconds=Dumper.number,
   inet_mac=Dumper.mac,
   ipv4_mtu=Dumper.number,
   ipv6_mtu=Dumper.number,
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
   return table.concat(result, "\n")
end

local function write_to_file(filename, content)
   local fd = assert(io.open(filename, "wt"),
      ("Couldn't open file: '%s'"):format(filename))
   fd:write(content)
   fd:close()
end

function dump_configuration(lwstate)
   local dest = (CONF_FILE_DUMP):format(os.date("%Y-%m-%d-%H:%M:%S"))
   print(("Dump lwAFTR configuration: '%s'"):format(dest))
   write_to_file(dest, do_dump_configuration(lwstate.conf))
end

function dump_binding_table(lwstate)
   print("Dump binding table")
   local content = {}
   local function write(str)
      table.insert(content, str)
   end
   local function dump()
      return table.concat(content, "\n")
   end
   local function format_entry(entry)
      local v6, v4, port_start, port_end, br_v6 = entry[1], entry[2], entry[3], entry[4], entry[5]
      local result = {}
      table.insert(result, ("'%s'"):format(ipv6:ntop(v6)))
      table.insert(result, ("'%s'"):format(ipv4number_to_str(v4)))
      table.insert(result, port_start)
      table.insert(result, port_end)
      if br_v6 then
         table.insert(result, ("'%s'"):format(ipv6:ntop(br_v6)))
      end
      return table.concat(result, ",")
   end
   -- Write entries to content
   write("{")
   for _, entry in ipairs(lwstate.binding_table) do
      write(("\t{%s},"):format(format_entry(entry)))
   end
   write("}")
   -- Dump content to file
   local filename = (BINDING_TABLE_FILE_DUMP):format(os.date("%Y-%m-%d-%H:%M:%S"))
   write_to_file(filename, dump())
   print(("Binding table written to %s"):format(filename))
end

function selftest ()
   print("selftest: dump")
   local icmp_policy = {
      DROP = 1,
      ALLOW = 2,
   }
   local conf = {
      binding_table = "binding_table.txt",
      aftr_ipv6_ip = ipv6:pton("fc00::100"),
      aftr_mac_inet_side = ethernet:pton("08:AA:AA:AA:AA:AA"),
      inet_mac = ethernet:pton("08:99:99:99:99:99"),
      ipv6_mtu = 9500,
      policy_icmpv6_incoming = icmp_policy.DROP,
      policy_icmpv6_outgoing = icmp_policy.DROP,
      icmpv6_rate_limiter_n_packets = 6e5,
      icmpv6_rate_limiter_n_seconds = 2,
      aftr_ipv4_ip = ipv4:pton("10.0.1.1"),
      aftr_mac_b4_side = ethernet:pton("02:AA:AA:AA:AA:AA"),
      next_hop6_mac = ethernet:pton("02:99:99:99:99:99"),
      ipv4_mtu = 1460,
      policy_icmpv4_incoming = icmp_policy.DROP,
      policy_icmpv4_outgoing = icmp_policy.DROP,
      vlan_tagging = true,
      v4_vlan_tag = 444,
      v6_vlan_tag = 666,
   }
   do_dump_configuration(conf)
   print("ok")
end
