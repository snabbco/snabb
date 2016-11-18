-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local lib  = require("core.lib")
local json = require("lib.json")
local usage = require("program.snabbnfv.neutron2snabb.README_inc")
local neutron2snabb_schema = require("program.snabbnfv.neutron2snabb.neutron2snabb_schema")

local NULL = "\\N"

function run (args)
   if #args ~= 2 and #args ~= 3 then
      print(usage) main.exit(1)
   end
   create_config(unpack(args))
end

-- The Neutron database tables that we need schema information to process.
schema_tables = {
   'ml2_network_segments', 'networks', 'ports', 'ml2_port_bindings',
   'securitygrouprules', 'securitygroupportbindings'
}

-- The default schema below is assumed if the database snapshot does
-- not include parsable table definitions.
default_schemas = {
   ml2_network_segments = {'id', 'network_id', 'network_type',
                           'physical_network', 'segmentation_id'},
   networks             = {'tenant_id', 'id', 'name', 'status',
                           'admin_state_up', 'shared'},
   ports                = {'tenant_id', 'id', 'name', 'network_id',
                           'mac_address', 'admin_state_up', 'status',
                           'device_id', 'device_owner'},
   ml2_port_bindings    = {'port_id', 'host', 'vif_type',
                           'vnic_type', 'profile', 'vif_details'},
   securitygrouprules   = {'tenant_id', 'id', 'security_group_id',
                           'remote_group_id', 'direction', 'ethertype',
                           'protocol', 'port_range_min', 'port_range_max',
                           'remote_ip_prefix'},
   securitygroupportbindings = {'port_id', 'security_group_id'}
}

-- Create a Snabb traffic process configuration.
--
-- INPUT_DIR contains the Neutron database dump.
--
-- OUTPUT_DIR will be populated with one file per physical_network.
-- The file says how to connect Neutron ports with provider VLANs.
--
-- HOSTNAME is optional and defaults to the local hostname.
function create_config (input_dir, output_dir, hostname)
   local ok, schema = pcall(neutron2snabb_schema.read, input_dir, schema_tables)
   if not ok then
      print("Warning - falling back to default schema because none found:")
      print("  "..schema)
      schema = default_schemas
   end
   local hostname = hostname or gethostname()
   local segments = parse_csv(input_dir.."/ml2_network_segments.txt",
                              schema.ml2_network_segments,
                              'id')
   local networks = parse_csv(input_dir.."/networks.txt",
                              schema.networks,
                              'id')
   local ports = parse_csv(input_dir.."/ports.txt",
                           schema.ports,
                           'id')
   local port_bindings = parse_csv(input_dir.."/ml2_port_bindings.txt",
                                   schema.ml2_port_bindings,
                                   'port_id')
   local secrules = parse_csv(input_dir.."/securitygrouprules.txt",
                              schema.securitygrouprules,
                              'security_group_id', true)
   local secbindings = parse_csv(input_dir.."/securitygroupportbindings.txt",
                                 schema.securitygroupportbindings,
                                 'port_id')
   print("Parsing neutron db tables")
   -- Compile zone configurations.
   local zones = {}
   for _, port in pairs(ports) do
      print("PortID: ", port.id)
      local binding = port_bindings[port.id]
      -- If the port is a 'vhostuser' port, lives on our host and is online
      -- then we compile its configuration.
      print("BindingID ", binding.id, " has vif_type ", binding.vif_type)
      if binding.vif_type == "vhostuser" then
         local vif_details = json.decode(binding.vif_details)
         -- See https://github.com/snabbco/snabb/pull/423
         local profile = vif_details["binding:profile"]
         profile = profile or {}
         print("vif_details has hostname ", vif_details.zone_host, "(we want ", hostname, ")")
         if vif_details.zone_host == hostname then
            local zone_port = vif_details.zone_port
            -- Each zone can have multiple port configurtions.
            if not zones[zone_port] then zones[zone_port] = {} end
            print("admin_state_ip is ", port.admin_state_up)
            if port.admin_state_up ~= '0' then
               print("Adding zone port '", zone_port, "' to list")
               -- Note: Currently we don't use `vif_details.zone_gbps'
               -- because its "not needed by the traffic process in the
               -- current implementation".
               table.insert(zones[zone_port],
                            { vlan = vif_details.zone_vlan,
                              mac_address = port.mac_address,
                              port_id = port.id,
                              ingress_filter = filter(port, secbindings, secrules, 'ingress'),
                              egress_filter = filter(port, secbindings, secrules, 'egress'),
                              stateful_filter = (profile.packetfilter ~= 'stateless'),
                              rx_police = profile.rx_police_gbps,
                              tx_police = profile.tx_police_gbps,
                              tunnel = tunnel(port, vif_details, profile) })
            end
         end
      end
   end
   -- Save the compiled zone configurations to output_dir.
   for id, ports in pairs(zones) do
      local output_path = output_dir.."/"..id
      lib.store_conf(output_path, ports)
      print("Created " .. output_path)
   end
end

  
-- Return the L2TPv3 tunnel expresion.
function tunnel (port, vif_details, profile)
   if profile.tunnel_type == "L2TPv3" then
      return { type = "L2TPv3",
               local_ip = vif_details.zone_ip,
               remote_ip = profile.l2tpv3_remote_ip,
               session = profile.l2tpv3_session,
               local_cookie = profile.l2tpv3_local_cookie,
               remote_cookie = profile.l2tpv3_remote_cookie,
               next_hop = profile.l2tpv3_next_hop }
   else return nil end
end

-- Parse FILENAME as a .csv file containing FIELDS.
-- Return a table from the KEY field to a record of all field values.
--
-- Example:
--   parse_csv("Luke	Gorrie	Lua\nJoe	Smith	C\n",
--             {"first", "last", "lang"},
--             "first")
-- Returns:
--   { Luke = { first = "Luke", last = "Gorrie", lang = "Lua" },
--     Joe  = { first = "Joe",  last = "Smith",  lang = "C" }
--   }
function parse_csv (filename, fields, key,  has_duplicates)
   local t = {}
   for line in io.lines(filename) do
      local record = {}
      local words = splitline(line)
      for i = 1, #words do
         record[fields[i]] = words[i]
      end
      if has_duplicates then
         if t[record[key]] == nil then t[record[key]] = {} end
         table.insert(t[record[key]], record)
      else
         t[record[key]] = record
      end
   end
   return t
end

-- Return an array of line's tab-delimited tokens.
function splitline (line)
   local words = {}
   for w in (line .. "\t"):gmatch("([^\t]*)\t") do
      table.insert(words, w)
   end
   return words
end

-- Get hostname.
function gethostname ()
   local hostname = lib.readcmd("hostname", "*l")
   if hostname then return hostname
   else error("Could not get hostname.") end
end


-- Translation of Security Groups into pflua filter expressions.
-- See selftest() below for examples of how this works.

-- Return the pcap filter expression to implement a security group.
function filter (port, secbindings, secrules, direction)
   direction = direction:lower()
   if secbindings[port.id] then
      local rules = secrules[secbindings[port.id].security_group_id]
      return rulestofilter(rules, direction)
   end
end

function rulestofilter (rules, direction)
   local t = {}
   for i = 1, #rules do
      local r = rules[i]
      for key, value in pairs(r) do
         if value == NULL then r[key] = nil
         elseif type(value) == 'string' then r[key] = value:lower() end
      end
      if r.direction == direction then
         t[#t+1] = ruletofilter(r, direction)
      end
   end
   if #t > 0 then return parenconcat(t, " or ") end
end

function ruletofilter (r, direction)
   local matches = {}           -- match rules to be combined
   local icmp
   if     r.ethertype == "ipv4" then matches[#matches+1] = "ip"  icmp = 'icmp'
   elseif r.ethertype == "ipv6" then matches[#matches+1] = "ip6" icmp = 'icmp6'
   else   error("unknown ethertype: " .. r.ethertype) end
   
   if     r.protocol == "tcp" then matches[#matches+1] = "tcp"
   elseif r.protocol == "udp" then matches[#matches+1] = "udp"
   elseif r.protocol == "icmp" then matches[#matches+1] = icmp end

   if r.port_range_min or r.port_range_max then
      local min = r.port_range_min or r.port_range_max
      local max = r.port_range_max or r.port_range_min
      matches[#matches+1] = ("dst portrange %d-%d"):format(min, max)
   end
   
   if r.remote_ip_prefix then
      local direction = ({ingress = "src", egress = "dst"})[direction]
      matches[#matches+1] = (direction.." net "..r.remote_ip_prefix)
   end

   local filter = parenconcat(matches, " and ")
   if r.ethertype == "ipv4" then filter = "(arp or "..filter..")" end
   return filter
end

-- Parenthesize and concatenate
function parenconcat (t, sep)
   if #t == 1 then return t[1] else return "("..table.concat(t, sep)..")" end
end

function selftest ()
   print("selftest: neutron2snabb")
   local function checkrule (rule, filter)
      local got = rulestofilter(lib.load_string(rule), 'ingress')
      if got ~= filter then
         print(([[Unexpected translation of %s"
  Expected: %q
    Actual: %q]]):format(
               rule, filter, got))
         error("selftest failed")
      else
         print(("ok: %s\n => %s"):format(rule, got))
      end
   end
   checkrule("{{direction='ingress', ethertype='IPv6'}}", 'ip6')
   checkrule("{{direction='ingress', ethertype='IPv4'}}", '(arp or ip)')
   checkrule("{{direction='ingress', ethertype='IPv4', protocol='tcp'}}",
             '(arp or (ip and tcp))')
   checkrule("{{direction='ingress', ethertype='IPv4', protocol='udp'}}", 
             '(arp or (ip and udp))')
   checkrule("{{direction='ingress', ethertype='IPv4', protocol='udp', port_range_min=1000}}",
             '(arp or (ip and udp and dst portrange 1000-1000))')
   checkrule("{{direction='ingress', ethertype='IPv4', protocol='udp', port_range_max=2000}}",
             '(arp or (ip and udp and dst portrange 2000-2000))')
   checkrule("{{direction='ingress', ethertype='IPv4', protocol='tcp', port_range_min=1000, port_range_max=2000}}",
             '(arp or (ip and tcp and dst portrange 1000-2000))')
   checkrule("{{direction='ingress', ethertype='IPv6', protocol='tcp'}, {direction='ingress', ethertype='IPv4', protocol='udp', remote_ip_prefix='10.0.0.0/8'}}",
             '((ip6 and tcp) or (arp or (ip and udp and src net 10.0.0.0/8)))')
   print("selftest ok")
end

