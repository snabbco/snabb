module(..., package.seeall)

local lib = require('core.lib')
local ffi = require('ffi')
local util = require('lib.yang.util')
local ipv4 = require('lib.protocol.ipv4')
local ctable = require('lib.ctable')
local binding_table = require("apps.lwaftr.binding_table")
local conf = require('apps.lwaftr.conf')
local load_lwaftr_config = conf.load_lwaftr_config
local ffi_array = require('lib.yang.util').ffi_array
local yang = require('lib.yang.yang')

local function show_usage(code)
   print(require("program.lwaftr.migrate_configuration.README_inc"))
   main.exit(code)
end

local function parse_args(args)
   local handlers = {}
   function handlers.h() show_usage(0) end
   args = lib.dogetopt(args, handlers, "h", { help="h" })
   if #args ~= 1 then show_usage(1) end
   return unpack(args)
end

local function migrate_conf(old)
   function convert_ipv4(addr)
      if addr then return util.ipv4_pton(ipv4:ntop(addr)) end
   end
   local external = {
      ip = convert_ipv4(old.aftr_ipv4_ip),
      mac = old.aftr_mac_inet_side,
      mtu = old.ipv4_mtu,
      ingress_filter = old.ipv4_ingress_filter,
      egress_filter = old.ipv4_egress_filter,
      allow_incoming_icmp = old.policy_icmpv4_incoming == conf.policies.ALLOW,
      generate_icmp_errors = old.policy_icmpv4_outgoing == conf.policies.ALLOW,
      vlan_tag = old.v4_vlan_tag,
      error_rate_limiting = {
         packets = old.icmpv4_rate_limiter_n_packets,
         seconds = old.icmpv4_rate_limiter_n_seconds
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
      allow_incoming_icmp = old.policy_icmpv6_incoming == conf.policies.ALLOW,
      generate_icmp_errors = old.policy_icmpv6_outgoing == conf.policies.ALLOW,
      vlan_tag = old.v6_vlan_tag,
      error_rate_limiting = {
         packets = old.icmpv6_rate_limiter_n_packets,
         seconds = old.icmpv6_rate_limiter_n_seconds
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

   local old_bt = binding_table.load(old.binding_table)
   local psid_map = {}
   for addr, end_addr, params in old_bt.psid_map:iterate() do
      local reserved_ports_bit_count = 16 - params.psid_length - params.shift
      if end_addr == addr then end_addr = nil end
      if reserved_ports_bit_count ~= 16 then
         psid_map[{addr=addr}] = {
            end_addr = end_addr,
            psid_length = params.psid_length,
            shift = params.shift,
            reserved_ports_bit_count = reserved_ports_bit_count
         }
      end
   end
   local br_address_t = ffi.typeof('uint8_t[16]')
   local br_address_array = ffi.cast (ffi.typeof('$*', br_address_t),
                                      old_bt.br_addresses)
   local br_addresses = ffi_array(br_address_array, br_address_t,
                                  old_bt.br_address_count)
   local softwires = old_bt.softwires

   return {
      external_interface = external,
      internal_interface = internal,
      binding_table = {
        psid_map = psid_map,
        br_address = br_addresses,
        softwire = softwires
      }
   }
end

function run(args)
   local conf_file = parse_args(args)
   local old_conf = load_lwaftr_config(conf_file)
   local new_conf = migrate_conf(old_conf)
   yang.print_data_for_schema_by_name('snabb-softwire-v1', new_conf, io.stdout)
   main.exit(0)
end
