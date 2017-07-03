module(..., package.seeall)

local lib = require('core.lib')
local ffi = require("ffi")
local ipv4 = require("lib.protocol.ipv4")
local rangemap = require("apps.lwaftr.rangemap")
local ctable = require("lib.ctable")
local cltable = require('lib.cltable')
local util = require('lib.yang.util')
local yang = require('lib.yang.yang')
local stream = require('lib.yang.stream')
local binding_table = require("apps.lwaftr.binding_table")
local Parser = require("program.lwaftr.migrate_configuration.conf_parser").Parser

local br_address_t = ffi.typeof('uint8_t[16]')
local SOFTWIRE_TABLE_LOAD_FACTOR = 0.4

local function show_usage(code)
   print(require("program.lwaftr.migrate_configuration.README_inc"))
   main.exit(code)
end

local function parse_args(args)
   local handlers = {}
   local version = 'legacy'
   function handlers.h() show_usage(0) end
   function handlers.f(v) version = string.lower(v) end
   args = lib.dogetopt(args, handlers, "hf:", { help="h", from="f" })
   if #args ~= 1 then show_usage(1) end
   return args[1], version
end

local policies = {
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

local function parse_psid_map(parser)
   local psid_info_spec = {
      parse={
         psid_length=Parser.parse_psid_param,
         shift=Parser.parse_psid_param
      },
      defaults={
         psid_length=function(config) return 16 - (config.shift or 16) end,
         shift=function(config) return 16 - (config.psid_length or 0) end
      },
      validate=function(parser, config)
         if config.psid_length + config.shift > 16 then
            parser:error('psid_length %d + shift %d should not exceed 16',
                         config.psid_length, config.shift)
         end
      end
   }

   local builder = rangemap.RangeMapBuilder.new(binding_table.psid_map_value_t)
   local value = binding_table.psid_map_value_t()
   parser:skip_whitespace()
   parser:consume_token('[%a_]', 'psid_map')
   parser:skip_whitespace()
   parser:consume('{')
   parser:skip_whitespace()
   while not parser:check('}') do
      local range_list = parser:parse_ipv4_range_list()
      local info = parser:parse_property_list(psid_info_spec, '{', '}')
      value.psid_length, value.shift = info.psid_length, info.shift
      for _, range in ipairs(range_list) do
         builder:add_range(range.min, range.max, value)
      end
      parser:skip_whitespace()
      if parser:check(',') or parser:check(';') then
         parser:skip_whitespace()
      end
   end
   return builder:build(binding_table.psid_map_value_t())
end

local function parse_br_addresses(parser)
   local addresses = {}
   parser:skip_whitespace()
   parser:consume_token('[%a_]', 'br_addresses')
   parser:skip_whitespace()
   parser:consume('{')
   parser:skip_whitespace()
   while not parser:check('}') do
      table.insert(addresses, parser:parse_ipv6())
      parser:skip_whitespace()
      if parser:check(',') then parser:skip_whitespace() end
   end
   local ret = util.ffi_array(ffi.new(ffi.typeof('$[?]', br_address_t),
                                      #addresses),
                              br_address_t, #addresses)
   for i, addr in ipairs(addresses) do ret[i] = addr end
   return ret
end

local function parse_softwires(parser, psid_map, br_address_count)
   local function required(key)
      return function(config)
         error('missing required configuration key "'..key..'"')
      end
   end
   local softwire_spec = {
      parse={
         ipv4=Parser.parse_ipv4_as_uint32,
         psid=Parser.parse_psid,
         b4=Parser.parse_ipv6,
         aftr=Parser.parse_non_negative_number
      },
      defaults={
         ipv4=required('ipv4'),
         psid=function(config) return 0 end,
         b4=required('b4'),
         aftr=function(config) return 0 end
      },
      validate=function(parser, config)
         local psid_length = psid_map:lookup(config.ipv4).value.psid_length
         if config.psid >= 2^psid_length then
            parser:error('psid %d out of range for IP', config.psid)
         end
         if config.aftr >= br_address_count then
            parser:error('only %d br addresses are defined', br_address_count)
         end
      end
   }

   local softwire_key_t = binding_table.softwire_key_t
   -- FIXME: Pull this type from the yang model, not out of thin air.
   local softwire_value_t = ffi.typeof[[
      struct {
         uint8_t b4_ipv6[16]; // Address of B4.
         uint32_t br;         // Which border router (lwAFTR IPv6 address)?
      } __attribute__((packed))
   ]]
   local map = ctable.new(
      { key_type = softwire_key_t, value_type = softwire_value_t })
   local key, value = softwire_key_t(), softwire_value_t()
   parser:skip_whitespace()
   parser:consume_token('[%a_]', 'softwires')
   parser:skip_whitespace()
   parser:consume('{')
   parser:skip_whitespace()
   while not parser:check('}') do
      local entry = parser:parse_property_list(softwire_spec, '{', '}')
      key.ipv4, key.psid = entry.ipv4, entry.psid
      value.br, value.b4_ipv6 = entry.aftr + 1, entry.b4
      local success = pcall(map.add, map, key, value)
      if not success then
         parser:error('duplicate softwire for ipv4=%s, psid=%d',
                      lwdebug.format_ipv4(key.ipv4), key.psid)
      end
      parser:skip_whitespace()
      if parser:check(',') then parser:skip_whitespace() end
   end
   map:resize(map.size / SOFTWIRE_TABLE_LOAD_FACTOR)
   return map
end

local function parse_binding_table(parser)
   local psid_map = parse_psid_map(parser)
   local br_addresses = parse_br_addresses(parser)
   local softwires = parse_softwires(parser, psid_map, #br_addresses)
   parser:skip_whitespace()
   parser:consume(nil)
   return { psid_map = psid_map,
            br_addresses = br_addresses,
            softwires = softwires }
end

function load_binding_table(file)
   local source = stream.open_input_byte_stream(file)
   return parse_binding_table(Parser.new(source:as_text_stream()))
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

   local old_bt = load_binding_table(old.binding_table)
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
      softwire_config = {
         external_interface = external,
         internal_interface = internal,
         binding_table = {
            psid_map = psid_map,
            br_address = old_bt.br_addresses,
            softwire = old_bt.softwires
         }
      }
   }
end

local function migrate_legacy(stream)
   local conf = Parser.new(stream):parse_property_list(lwaftr_conf_spec)
   return migrate_conf(conf)
end

local function increment_br(conf)
   for entry in conf.softwire_config.binding_table.softwire:iterate() do
      -- Sadly it's not easy to make an updater that always works for
      -- the indexing change, because changing the default from 0 to 1
      -- makes it ambiguous whether a "br" value of 1 comes from the new
      -- default, or was present as such in the old configuration.  Sad.
      if entry.value.br ~= 1 then
         entry.value.br = entry.value.br + 1
      end
   end
   if #conf.softwire_config.binding_table.br_address > 1 then
      io.stderr:write('Migrator unable to tell whether br=1 entries are '..
                         'due to new default or old setting; manual '..
                         'verification needed.\n')
      io.stderr:flush()
   end
   return conf
end

local function migrate_3_0_1(conf_file)
   local data = require('lib.yang.data')
   local str = "softwire-config {\n"..io.open(conf_file, 'r'):read('*a').."\n}"
   return increment_br(data.load_data_for_schema_by_name(
                          'snabb-softwire-v1', str, conf_file))
end

local function migrate_3_0_1bis(conf_file)
   return increment_br(yang.load_configuration(
                          conf_file, {schema_name='snabb-softwire-v1'}))
end

local migrators = { legacy = migrate_legacy, ['3.0.1'] = migrate_3_0_1,
                    ['3.0.1.1'] = migrate_3_0_1bis }
function run(args)
   local conf_file, version = parse_args(args)
   local migrate = migrators[version]
   if not migrate then
      io.stderr:write("error: unknown version: "..version.."\n")
      show_usage(1)
   end
   local conf = migrate(conf_file)
   yang.print_data_for_schema_by_name('snabb-softwire-v1', conf, io.stdout)
   main.exit(0)
end
