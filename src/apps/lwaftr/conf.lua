module(..., package.seeall)

local yang = require('lib.yang.yang')

function load_lwaftr_config(filename)
   -- FIXME: apply constraints on config:
   -- next_hop6_mac=required_at_least_one_of('next_hop6_mac', 'next_hop_ipv6_addr'),
   -- inet_mac=required_at_least_one_of('inet_mac', 'next_hop_ipv4_addr'),
   -- next_hop_ipv4_addr = required_at_least_one_of('next_hop_ipv4_addr', 'inet_mac'),
   -- next_hop_ipv6_addr = required_at_least_one_of('next_hop_ipv6_addr', 'next_hop6_mac'),
   -- v4_vlan_tag=required_if('v4_vlan_tag', 'vlan_tagging'),
   -- v6_vlan_tag=required_if('v6_vlan_tag', 'vlan_tagging'),
   return yang.load_configuration(filename,
                                  {schema_name='snabb-softwire-v1'})
end

function selftest()
   print('selftest: conf')
   print('ok')
end
