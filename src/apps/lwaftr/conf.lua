module(..., package.seeall)

local ethernet = require("lib.protocol.ethernet")
local ffi = require("ffi")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local util = require("lib.yang.util")
local yang = require('lib.yang.yang')
local cltable = require('lib.cltable')
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

local function required_if(key, otherkey)
   return function(config)
      if config[otherkey] then
         error('missing required configuration key "'..key..'"')
      end
   end
end

local function required_at_least_one_of(key, otherkey)
   return function(config)
      if config[otherkey] == nil then
         error(string.format("At least one of '%s' and '%s' must be specified", key, otherkey))
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
      next_hop6_mac=Parser.parse_mac,
      binding_table=Parser.parse_file_name,
      hairpinning=Parser.parse_boolean,
      icmpv4_rate_limiter_n_packets=Parser.parse_non_negative_number,
      icmpv4_rate_limiter_n_seconds=Parser.parse_positive_number,
      icmpv6_rate_limiter_n_packets=Parser.parse_non_negative_number,
      icmpv6_rate_limiter_n_seconds=Parser.parse_positive_number,
      inet_mac=Parser.parse_mac,
      ipv4_mtu=Parser.parse_mtu,
      ipv6_mtu=Parser.parse_mtu,
      max_fragments_per_reassembly_packet=Parser.parse_positive_number,
      max_ipv4_reassembly_packets=Parser.parse_positive_number,
      max_ipv6_reassembly_packets=Parser.parse_positive_number,
      next_hop_ipv4_addr=Parser.parse_ipv4,
      next_hop_ipv6_addr=Parser.parse_ipv6,
      policy_icmpv4_incoming=Parser.enum_parser(policies),
      policy_icmpv4_outgoing=Parser.enum_parser(policies),
      policy_icmpv6_incoming=Parser.enum_parser(policies),
      policy_icmpv6_outgoing=Parser.enum_parser(policies),
      v4_vlan_tag=Parser.parse_vlan_tag,
      v6_vlan_tag=Parser.parse_vlan_tag,
      vlan_tagging=Parser.parse_boolean,
      ipv4_ingress_filter=Parser.parse_string_or_file,
      ipv4_egress_filter=Parser.parse_string_or_file,
      ipv6_ingress_filter=Parser.parse_string_or_file,
      ipv6_egress_filter=Parser.parse_string_or_file,
   },
   defaults={
      aftr_ipv4_ip=required('aftr_ipv4_ip'),
      aftr_ipv6_ip=required('aftr_ipv6_ip'),
      aftr_mac_b4_side=required('aftr_mac_b4_side'),
      aftr_mac_inet_side=required('aftr_mac_inet_side'),
      next_hop6_mac=required_at_least_one_of('next_hop6_mac', 'next_hop_ipv6_addr'),
      binding_table=required('binding_table'),
      hairpinning=default(true),
      icmpv4_rate_limiter_n_packets=default(6e5),
      icmpv4_rate_limiter_n_seconds=default(2),
      icmpv6_rate_limiter_n_packets=default(6e5),
      icmpv6_rate_limiter_n_seconds=default(2),
      inet_mac=required_at_least_one_of('inet_mac', 'next_hop_ipv4_addr'),
      ipv4_mtu=default(1460),
      ipv6_mtu=default(1500),
      max_fragments_per_reassembly_packet=default(40),
      max_ipv4_reassembly_packets=default(20000), -- Just under 500 megs memory
      max_ipv6_reassembly_packets=default(20000), -- Just under 500 megs memory
      next_hop_ipv4_addr = required_at_least_one_of('next_hop_ipv4_addr', 'inet_mac'),
      next_hop_ipv6_addr = required_at_least_one_of('next_hop_ipv6_addr', 'next_hop6_mac'),
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

function migrate_conf(old)
   function convert_ipv4(addr)
      if addr then return util.ipv4_pton(ipv4:ntop(addr)) end
   end
   local external = {
      ip = convert_ipv4(old.aftr_ipv4_ip),
      mac = old.aftr_mac_inet_side,
      mtu = old.ipv4_mtu,
      ingress_filter = old.ipv4_ingress_filter,
      egress_filter = old.ipv4_egress_filter,
      allow_incoming_icmp = old.policy_icmpv4_incoming == policies.ALLOW,
      generate_icmp_errors = old.policy_icmpv4_outgoing == policies.ALLOW,
      vlan_tag = old.v4_vlan_tag,
      error_rate_limiting = {
         packets = old.icmpv4_rate_limiter_n_packets,
         period = old.icmpv4_rate_limiter_n_seconds
      },
      reassembly = {
         max_fragments_per_packet = old.max_fragments_per_reassembly_packet,
         max_packets = old.max_ipv4_reassembly_packets
      },
      next_hop = {
         ip = convert_ipv4(old.next_hop_ipv4_addr),
         mac = old.inet_mac
      }
   }

   local internal = {
      ip = old.aftr_ipv6_ip,
      mac = old.aftr_mac_b4_side,
      mtu = old.ipv6_mtu,
      ingress_filter = old.ipv6_ingress_filter,
      egress_filter = old.ipv6_egress_filter,
      allow_incoming_icmp = old.policy_icmpv6_incoming == policies.ALLOW,
      generate_icmp_errors = old.policy_icmpv6_outgoing == policies.ALLOW,
      vlan_tag = old.v6_vlan_tag,
      error_rate_limiting = {
         packets = old.icmpv6_rate_limiter_n_packets,
         period = old.icmpv6_rate_limiter_n_seconds
      },
      reassembly = {
         max_fragments_per_packet = old.max_fragments_per_reassembly_packet,
         max_packets = old.max_ipv6_reassembly_packets
      },
      next_hop = {
         ip = old.next_hop_ipv6_addr,
         mac = old.next_hop6_mac
      },
      hairpinning = old.hairpinning
   }

   local binding_table = require("apps.lwaftr.binding_table")
   local old_bt = binding_table.load_legacy(old.binding_table)
   local psid_key_t = ffi.typeof('struct { uint32_t addr; }')
   local psid_map = cltable.new({ key_type = psid_key_t })
   for addr, end_addr, params in old_bt.psid_map:iterate() do
      local reserved_ports_bit_count = 16 - params.psid_length - params.shift
      if end_addr == addr then end_addr = nil end
      if reserved_ports_bit_count ~= 16 then
         psid_map[psid_key_t(addr)] = {
            end_addr = end_addr,
            psid_length = params.psid_length,
            shift = params.shift,
            reserved_ports_bit_count = reserved_ports_bit_count
         }
      end
   end

   return {
      external_interface = external,
      internal_interface = internal,
      binding_table = {
        psid_map = psid_map,
        br_address = old_bt.br_addresses,
        softwire = old_bt.softwires
      }
   }
end

function load_legacy_lwaftr_config(stream)
   local conf = Parser.new(stream):parse_property_list(lwaftr_conf_spec)
   return migrate_conf(conf)
end

function load_lwaftr_config(filename)
   return yang.load_configuration(filename,
                                  {schema_name='snabb-softwire-v1'})
end

function selftest()
   print('selftest: conf')
   print('ok')
end
