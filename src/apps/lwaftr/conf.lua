module(..., package.seeall)

local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")

local bt = require("apps.lwaftr.binding_table")
local Parser = require("apps.lwaftr.conf_parser").Parser

policies = {
   DROP = 1,
   ALLOW = 2
}

local function required(key)
   return function(config)
      error('missing required configuration key "'..key..'"')
   end
end

local function required_if(key, pred)
   return function(config)
      if config[pred] then
         error('missing required configuration key "'..key..'"')
      end
   end
end

local function default(val)
   return function(config) return val end
end

local lwaftr_conf_spec = {
   parse={
      aftr_ipv4_ip=Parser.parse_ipv4,
      aftr_ipv6_ip=Parser.parse_ipv6,
      aftr_mac_b4_side=Parser.parse_mac,
      aftr_mac_inet_side=Parser.parse_mac,
      b4_mac=Parser.parse_mac,
      binding_table=Parser.parse_file_name,
      hairpinning=Parser.parse_boolean,
      icmpv6_rate_limiter_n_packets=Parser.parse_non_negative_number,
      icmpv6_rate_limiter_n_seconds=Parser.parse_positive_number,
      inet_mac=Parser.parse_mac,
      ipv4_mtu=Parser.parse_mtu,
      ipv6_mtu=Parser.parse_mtu,
      policy_icmpv4_incoming=Parser.enum_parser(policies),
      policy_icmpv4_outgoing=Parser.enum_parser(policies),
      policy_icmpv6_incoming=Parser.enum_parser(policies),
      policy_icmpv6_outgoing=Parser.enum_parser(policies),
      v4_vlan_tag=Parser.parse_vlan_tag,
      v6_vlan_tag=Parser.parse_vlan_tag,
      vlan_tagging=Parser.parse_boolean
   },
   defaults={
      aftr_ipv4_ip=required('aftr_ipv4_ip'),
      aftr_ipv6_ip=required('aftr_ipv6_ip'),
      aftr_mac_b4_side=required('aftr_mac_b4_side'),
      aftr_mac_inet_side=required('aftr_mac_inet_side'),
      b4_mac=required('b4_mac'),
      binding_table=required('binding_table'),
      hairpinning=default(true),
      icmpv6_rate_limiter_n_packets=default(6e5),
      icmpv6_rate_limiter_n_seconds=default(2),
      inet_mac=required('inet_mac'),
      ipv4_mtu=default(1460),
      ipv6_mtu=default(1500),
      policy_icmpv4_incoming=default(policies.ALLOW),
      policy_icmpv4_outgoing=default(policies.ALLOW),
      policy_icmpv6_incoming=default(policies.ALLOW),
      policy_icmpv6_outgoing=default(policies.ALLOW),
      v4_vlan_tag=required_if('v4_vlan_tag', 'vlan_tagging'),
      v6_vlan_tag=required_if('v6_vlan_tag', 'vlan_tagging'),
      vlan_tagging=default(false)
   },
   validate=function(parser, config) end
}

local function parse_lwaftr_conf(stream)
   return Parser.new(stream):parse_property_list(lwaftr_conf_spec)
end

-- TODO: rewrite this after netconf integration
local function read_conf(conf_file)
   local input = io.open(conf_file)
   local conf_vars = input:read('*a')
   local full_config = ([[
      function _conff(policies, ipv4, ipv6, ethernet, bt)
         return {%s}
      end
      return _conff
   ]]):format(conf_vars)
   local conf = assert(loadstring(full_config))()
   return conf(policies, ipv4, ipv6, ethernet, bt)
end

local aftrconf
function get_aftrconf(conf_file)
   if not aftrconf then
      aftrconf = read_conf(conf_file)
   end
   return aftrconf
end

function selftest()
   print('selftest: conf')
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
   local function test(str, expected)
      if not equal(expected, parse_lwaftr_conf(string_file(str))) then
         error('lwaftr conf parse produced unexpected result; string:\n'..str)
      end
   end
   test([[
            aftr_ipv4_ip = 1.2.3.4
            aftr_ipv6_ip = 8:9:a:b:c:d:e:f
            aftr_mac_b4_side = 22:22:22:22:22:22
            aftr_mac_inet_side = 12:12:12:12:12:12
            b4_mac = 44:44:44:44:44:44
            binding_table = "foo.table"
            hairpinning = true
            icmpv6_rate_limiter_n_packets=6e3
            icmpv6_rate_limiter_n_seconds=2
            inet_mac = 68:68:68:68:68:68
            ipv4_mtu = 1460
            ipv6_mtu = 1500
            policy_icmpv4_incoming = ALLOW
            policy_icmpv6_incoming = ALLOW
            policy_icmpv4_outgoing = ALLOW
            policy_icmpv6_outgoing = ALLOW
            v4_vlan_tag = 1092 # 0x444
            v6_vlan_tag = 1638 # 0x666
            vlan_tagging = true
        ]],
      {
         aftr_ipv4_ip = ipv4:pton('1.2.3.4'),
         aftr_ipv6_ip = ipv6:pton('8:9:a:b:c:d:e:f'),
         aftr_mac_b4_side = ethernet:pton("22:22:22:22:22:22"),
         aftr_mac_inet_side = ethernet:pton("12:12:12:12:12:12"),
         b4_mac = ethernet:pton("44:44:44:44:44:44"),
         binding_table = "foo.table",
         hairpinning = true,
         icmpv6_rate_limiter_n_packets=6e3,
         icmpv6_rate_limiter_n_seconds=2,
         inet_mac = ethernet:pton("68:68:68:68:68:68"),
         ipv4_mtu = 1460,
         ipv6_mtu = 1500,
         policy_icmpv4_incoming = policies['ALLOW'],
         policy_icmpv6_incoming = policies['ALLOW'],
         policy_icmpv4_outgoing = policies['ALLOW'],
         policy_icmpv6_outgoing = policies['ALLOW'],
         v4_vlan_tag = 0x444,
         v6_vlan_tag = 0x666,
         vlan_tagging = true
      }
   )
   print('ok')
end
