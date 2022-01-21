module(..., package.seeall)

local lib = require('core.lib')
local ffi = require("ffi")
local ipv4 = require("lib.protocol.ipv4")
local rangemap = require("apps.lwaftr.rangemap")
local ctable = require("lib.ctable")
local cltable = require('lib.cltable')
local mem = require('lib.stream.mem')
local util = require('lib.yang.util')
local yang = require('lib.yang.yang')
local binding_table = require("apps.lwaftr.binding_table")
local Parser = require("program.lwaftr.migrate_configuration.conf_parser").Parser
local data = require('lib.yang.data')
local schema = require('lib.yang.schema')

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

   local softwire_key_t = ffi.typeof[[
     struct {
         uint32_t ipv4;       // Public IPv4 address of this softwire (host-endian).
         uint16_t padding;    // Zeroes.
         uint16_t psid;       // Port set ID.
     } __attribute__((packed))
   ]]
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
      value.br, value.b4_ipv6 = entry.aftr, entry.b4
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

function load_binding_table(filename)
   return parse_binding_table(Parser.new(filename))
end


local function config_to_string(schema, conf)
   if type(schema) == "string" then
      schema = yang.load_schema_by_name(schema)
   end
   return mem.call_with_output_string(
      yang.print_config_for_schema, schema, conf)
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

   -- Build a version of snabb-softwire-v1 with a 0-based index so increment_br
   -- does the correct thing.
   local schema = yang.load_schema_by_name("snabb-softwire-v1")
   local bt = schema.body["softwire-config"].body["binding-table"].body
   bt.softwire.body.br.default = "0"
   return config_to_string(schema, {
      softwire_config = {
         external_interface = external,
         internal_interface = internal,
         binding_table = {
            psid_map = psid_map,
            br_address = old_bt.br_addresses,
            softwire = old_bt.softwires
         }
      }
   })
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
   return config_to_string('snabb-softwire-v1', conf)
end

local function remove_address_list(conf)
   local bt = conf.softwire_config.binding_table
   for key, entry in cltable.pairs(bt.softwire) do
      local br = entry.br or 1
      entry.br_address = assert(bt.br_address[br])
      entry.br = nil
   end
   return conf
end

local function remove_psid_map(conf)
   -- We're actually going to load the psidmap in the schema so ranges can easily be
   -- looked up. With support of end-addr simply trying to lookup by addr will fail.
   -- Luckily this is the last time this should bother us hopefully.
   local function load_range_map(conf)
      local rangemap = require("apps.lwaftr.rangemap")
      local psid_map_value_t = binding_table.psid_map_value_t

      -- This has largely been taken from the binding_table.lua at 3db2896
      -- however it only builds the psidmap and not the entire binding table.
      local psid_builder = rangemap.RangeMapBuilder.new(psid_map_value_t)
      local psid_value = psid_map_value_t()
      for k, v in cltable.pairs(conf.psid_map) do
         local psid_length, shift = v.psid_length, v.shift
         shift = shift or 16 - psid_length - (v.reserved_ports_bit_count or 0)
         assert(psid_length + shift <= 16,
               'psid_length '..psid_length..' + shift '..shift..
               ' should not exceed 16')
         psid_value.psid_length, psid_value.shift = psid_length, shift
         psid_builder:add_range(k.addr, v.end_addr or k.addr, psid_value)
      end
      return psid_builder:build(psid_map_value_t())
   end

   local psid_map = load_range_map(conf.softwire_config.binding_table)

   -- Remove the psid-map and add it to the softwire.
   local bt = conf.softwire_config.binding_table
   for key, entry in cltable.pairs(bt.softwire) do
      -- Find the port set for the ipv4 address
      local port_set = psid_map:lookup(key.ipv4)
      assert(port_set, "Unable to migrate conf: softwire without psidmapping")

      -- Add the psidmapping to the softwire
      local shift, length = port_set.value.shift, port_set.value.psid_length
      entry.port_set = {
         psid_length=length,
         reserved_ports_bit_count=(16 - shift - length)
      }
   end

   return conf
end

local function v3_migration(src, conf_file)
   local v2_schema = yang.load_schema_by_name("snabb-softwire-v2")
   local v3_schema = yang.load_schema_by_name("snabb-softwire-v3")
   local conf = yang.load_config_for_schema(
      v2_schema, mem.open_input_string(src, conf_file))

   -- Move leaf external-interface/device up as external-device.
   for device, instance in pairs(conf.softwire_config.instance) do
      for id, queue in pairs(instance.queue) do
         if queue.external_interface.device then
	    if instance.external_device then
	       io.stderr:write('Multiple external devices detected; '..
                               'manual verification needed.\n')
               io.stderr:flush()
	    end
	    instance.external_device = queue.external_interface.device
	    queue.external_interface.device = nil
	 end
      end
   end

   return config_to_string(v3_schema, conf)   
end

local function multiprocess_migration(src, conf_file)
   local device = "IPv6 PCI Address"
   local ex_device = "IPv4 PCI address"

   -- We should build up a hybrid schema from parts of v1 and v2.
   local v1_schema = yang.load_schema_by_name("snabb-softwire-v1")
   -- Make sure we load a fresh schema, as not to mutate a memoized copy
   local hybridscm = schema.load_schema(schema.load_schema_source_by_name("snabb-softwire-v2"))
   local v1_external = v1_schema.body["softwire-config"].body["external-interface"]
   local v1_internal = v1_schema.body["softwire-config"].body["internal-interface"]
   local external = hybridscm.body["softwire-config"].body["external-interface"]
   local internal = hybridscm.body["softwire-config"].body["internal-interface"]
   local queue = hybridscm.body["softwire-config"].body.instance.body.queue

   -- Remove the mandatory requirements
   queue.body["external-interface"].body.ip.mandatory = false
   queue.body["external-interface"].body.mac.mandatory = false
   queue.body["external-interface"].body["next-hop"].mandatory = false
   queue.body["internal-interface"].body.ip.mandatory = false
   queue.body["internal-interface"].body.mac.mandatory = false
   queue.body["internal-interface"].body["next-hop"].mandatory = false

   hybridscm.body["softwire-config"].body["external-interface"] = v1_external
   hybridscm.body["softwire-config"].body["internal-interface"] = v1_internal

   -- Extract the grammar, load the config and find the key
   local hybridgmr = data.config_grammar_from_schema(hybridscm)
   local instgmr = hybridgmr.members["softwire-config"].members.instance
   local conf = yang.load_config_for_schema(
      hybridscm, mem.open_input_string(src, conf_file))
   local queue_key = ffi.typeof(instgmr.values.queue.key_ctype)
   local global_external_if = conf.softwire_config.external_interface
   local global_internal_if = conf.softwire_config.internal_interface
   -- If there is a external device listed we should include that too.


   -- Build up the instance list
   local instance = {
      [device] = {queue={}},
   }
   local key = 0
   local value = {
      external_interface = {
         device = ex_device,
         ip = conf.softwire_config.external_interface.ip,
         mac = conf.softwire_config.external_interface.mac,
         next_hop = {},
         vlan_tag = conf.softwire_config.external_interface.vlan_tag
      },
      internal_interface = {
         ip = conf.softwire_config.internal_interface.ip,
         mac = conf.softwire_config.internal_interface.mac,
         next_hop = {},
         vlan_tag = conf.softwire_config.internal_interface.vlan_tag
      }
   }

   -- Add the list to the config
   if global_external_if.next_hop.mac then
      value.external_interface.next_hop.mac = global_external_if.next_hop.mac
   elseif global_external_if.next_hop.ip then
      value.external_interface.next_hop.ip = global_external_if.next_hop.ip
   else
      error("One or both of next-hop values must be provided.")
   end

   if global_internal_if.next_hop.mac then
      value.internal_interface.next_hop.mac = global_internal_if.next_hop.mac
   elseif global_internal_if.next_hop.ip then
      value.internal_interface.next_hop.ip = global_internal_if.next_hop.ip
   else
      error("One or both of next-hop values must be provided.")
   end
   instance[device].queue[key] = value
   conf.softwire_config.instance = instance

   -- Remove the fields which no longer should exist
   conf.softwire_config.internal_interface.ip = nil
   conf.softwire_config.internal_interface.mac = nil
   conf.softwire_config.internal_interface.next_hop = nil
   conf.softwire_config.internal_interface.vlan_tag = nil
   conf.softwire_config.external_interface.ip = nil
   conf.softwire_config.external_interface.mac = nil
   conf.softwire_config.external_interface.next_hop = nil
   conf.softwire_config.external_interface.vlan_tag = nil

   return config_to_string(hybridscm, conf)
end

local function v2_migration(src, conf_file)
   -- Lets create a custom schema programmatically as an intermediary so we can
   -- switch over to v2 of snabb-softwire config.
   local v1_schema = yang.load_schema_by_name("snabb-softwire-v1")
   local v1_binding_table = v1_schema.body["softwire-config"].body["binding-table"]
   
   -- Make sure we load a fresh schema, as not to mutate a memoized copy
   local hybridscm = schema.load_schema(schema.load_schema_source_by_name("snabb-softwire-v2"))
   local binding_table = hybridscm.body["softwire-config"].body["binding-table"]

   -- Add the schema from v1 that we need to convert them.
   binding_table.body["br-address"] = v1_binding_table.body["br-address"]
   binding_table.body["psid-map"] = v1_binding_table.body["psid-map"]
   binding_table.body.softwire.body.br = v1_binding_table.body.softwire.body.br
   binding_table.body.softwire.body.padding = v1_binding_table.body.softwire.body.padding

   -- Add the external and internal interfaces
   local hybridconfig = hybridscm.body["softwire-config"]
   local v1config = v1_schema.body["softwire-config"]
   hybridconfig.body["external-interface"] = v1config.body["external-interface"]
   hybridconfig.body["internal-interface"] = v1config.body["internal-interface"]

   -- Remove the mandatory requirement on softwire.br-address for the migration
   binding_table.body["softwire"].body["br-address"].mandatory = false

   -- Remove the mandatory requirement on softwire.port-set.psid-length for the migration
   binding_table.body["softwire"].body["port-set"].body["psid-length"].mandatory = false

   local conf = yang.load_config_for_schema(
      hybridscm, mem.open_input_string(src, conf_file))

   -- Remove the br-address leaf-list and add it onto the softwire.
   conf = remove_address_list(conf)
   conf.softwire_config.binding_table.br_address = nil

   -- Remove the psid-map and add it to the softwire.
   conf = remove_psid_map(conf)
   conf.softwire_config.binding_table.psid_map = nil

   return config_to_string(hybridscm, conf)
end

local function migrate_legacy(stream)
   local conf = Parser.new(stream):parse_property_list(lwaftr_conf_spec)
   conf = migrate_conf(conf)
   return conf
end


local function migrate_3_0_1(conf_file, src)
   if src:sub(0, 15) == "softwire-config" then
      return src
   else
      return "softwire-config { "..src.." }"
   end
end

local function migrate_3_0_1bis(conf_file, src)
   return increment_br(
      yang.load_config_for_schema_by_name(
         'snabb-softwire-v1', mem.open_input_string(src, conf_file)))
end

local function migrate_3_2_0(conf_file, src)
   return v2_migration(src, conf_file)
end

local function migrate_2017_07_01(conf_file, src)
   return multiprocess_migration(src, conf_file)
end

local function migrate_2022_01_19(conf_file, src)
   return v3_migration(src, conf_file)
end


local migrations = {
   {version='legacy',    migrator=migrate_legacy},
   {version='3.0.1',     migrator=migrate_3_0_1},
   {version='3.0.1.1',   migrator=migrate_3_0_1bis},
   {version='3.2.0',     migrator=migrate_3_2_0},
   {version='2017.07.01',migrator=migrate_2017_07_01},
   {version='2022.01.19',migrator=migrate_2022_01_19},
}


function run(args)
   local conf_file, version = parse_args(args)

   -- Iterate over migrations until we've found the
   local start
   for id, migration in pairs(migrations) do
      if migration.version == version then
         start = id - 1
      end
   end
   if start == nil then
      io.stderr:write("error: unknown version: "..version.."\n")
      show_usage(1)
   end

   local conf = io.open(conf_file, "r"):read("*a")
   for _, migration in next,migrations,start do
      io.stderr:write(("-> %s migration\n"):format(migration.version))
      conf = migration.migrator(conf_file, conf)
      -- Prompt the garbage collection to do a full collect after each migration
      collectgarbage()
   end

   print(conf)
   main.exit(0)
end
