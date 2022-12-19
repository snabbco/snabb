-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local path_data = require("lib.yang.path_data")
local support = require("lib.ptree.support")
local shm = require("core.shm")
local counter = require("core.counter")


local function collect_pci_states (pid)
   local states = {}
   for _, device in ipairs(shm.children("/"..pid.."/pci")) do
      local stats = shm.open_frame("/"..pid.."/pci/"..device)
      local queue_stats = {}
      for name, c in pairs(stats) do
         local queue = name:match("^rxdrop_(%d+)$") -- Connect-X
                    or name:match("^q(%d+)_rxdrops$") -- Intel_mp
         if queue then
            queue_stats[tonumber(queue)] = {
               packets_dropped = counter.read(c)
            }
         end
      end
      table.insert(states, {
         device = device,
         packets_received = counter.read(stats.rxpackets),
         packets_dropped = counter.read(stats.rxdrop),
         queue = queue_stats
      })
   end
   return states
end

local function collect_template_states (pid, app, exporter)
   local states = {}
   local templates_path = "/"..pid.."/ipfix_templates/"..exporter
   for _, id in ipairs(shm.children(templates_path)) do
      local id = assert(tonumber(id))
      local stats = shm.open_frame(templates_path.."/"..id)
      local function table_state (prefix, other)
         local state = other or {}
         state.occupancy = counter.read(stats[prefix..'occupancy'])
         state.size = counter.read(stats[prefix..'size'])
         state.byte_size = counter.read(stats[prefix..'byte_size'])
         state.max_displacement = counter.read(stats[prefix..'max_displacement'])
         state.load_factor = tonumber(state.occupancy)/tonumber(state.size)
         return state
      end
      states[id] = {
         packets_processed = counter.read(stats.packets_in),
         flows_exported = counter.read(stats.exported_flows),
         flow_export_packets = counter.read(stats.flow_export_packets),
         flow_table = table_state("table_", {
            last_scan_time = counter.read(stats.table_scan_time)
         }),
         flow_export_rate_table = table_state("rate_table_")
      }
   end
   return states
end

local function find_rss_link (pid, app)
   for _, link in ipairs(shm.children("/"..pid.."/links")) do
      local rss_link = link:match(("^([%%w_]+%%.[%%w_]+) *-> *%s.input$"):format(app))
      if rss_link then
         return rss_link
      end
   end
   error("No RSS link for: "..app.." (pid: "..pid..")")
end

local function collect_ipfix_states (pid, rss_links)
   local states = {}
   for _, app in ipairs(shm.children("/"..pid.."/apps")) do
      local exporter, instance = app:match("^ipfix_([%w_]+)_(%d+)$")
      if exporter then
         local stats = shm.open_frame("/"..pid.."/apps/"..app)
         local state = {
            id = tonumber(instance),
            pid = pid,
            observation_domain = tonumber(counter.read(stats.observation_domain)),
            packets_received = counter.read(stats.received_packets),
            packets_ignored = counter.read(stats.ignored_packets),
            template_packets_transmitted = counter.read(stats.template_packets),
            sequence_number = counter.read(stats.sequence_number)
         }
         state.template = collect_template_states(pid, app, exporter.."_"..instance)
         rss_links[find_rss_link(pid, app)] = state.observation_domain
         states[exporter] = state
      end
   end
   return states
end

function collect_rss_states (pid, rss_links)
   local states = {}
   local id
   for _, link in ipairs(shm.children("/"..pid.."/links")) do
      local rss_group = tonumber(link:match("^rss(%d+)%."))
      if rss_group then
         id = tonumber(rss_group)
      end
      for rss_link, _ in pairs(rss_links) do
         if (link:match("^"..rss_link) and link:match("^rss%d+%.")) -- embedded link
         or (link:match("-> *"..rss_link:gsub("%.output$", ".input").."$")) -- interlink
         then
            local stats = shm.open_frame("/"..pid.."/links/"..link)
            local observation_domain = rss_links[rss_link]
            states[observation_domain] = {
               id = id,
               pid = pid,
               txdrop = counter.read(stats.txdrop)
            }
            break
         end
      end
   end
   return states
end

function collect_queue_state (interfaces, rxq)
   local queue_state = {}
   for device, interface in pairs(interfaces) do
      queue_state[device] = interface.queue[rxq]
   end
   return queue_state
end

local function compute_pid_reader ()
   return function (pid) return pid end
end

local function get_state_grammar (path)
   return path_data.grammar_for_schema_by_name(
      'snabb-snabbflow-v1', '/snabbflow-state/'..path, false
   )
end

local function process_states (pids)
   local state = {
      interface = {},
      exporter = {},
      rss_group = {}
   }
   -- Collect PCI device states
   for _, pid in ipairs(pids) do
      local states = collect_pci_states(pid)
      for _, pci_state in ipairs(states) do
         state.interface[pci_state.device] = pci_state
      end
   end
   -- Mapping between software RSS links and IPFIX instances
   local rss_links = {}
   -- Collect IPFIX instance states
   local ipfix_states = {}
   for _, pid in ipairs(pids) do
      local states = collect_ipfix_states(pid, rss_links)
      for exporter, ipfix_state in pairs(states) do
         ipfix_states[exporter] = ipfix_states[exporter] or {}
         table.insert(ipfix_states[exporter], ipfix_state)
      end
   end
   -- Collect RSS states
   local rss_states = {}
   for _, pid in ipairs(pids) do
      local states = collect_rss_states(pid, rss_links)
      for observation_domain, rss_state in pairs(states) do
         rss_states[observation_domain] = rss_state
      end
   end
   -- Enrich IPFIX instance states with software RSS link drop counts
   for _, states in pairs(ipfix_states) do
      for _, ipfix_state in ipairs(states) do
         local observation_domain = ipfix_state.observation_domain
         ipfix_state.packets_dropped = rss_states[observation_domain].txdrop
      end
   end
   -- Aggregate IPFIX exporter states
   local function agg (tdst, tsrc, field)
      tdst[field] = (tdst[field] or 0ULL) + tsrc[field]
   end
   for exporter, states in pairs(ipfix_states) do
      state.exporter[exporter] = state.exporter[exporter] or {}
      local exporter = state.exporter[exporter]
      exporter.template = exporter.template or {}
      local templates = exporter.template
      for _, ipfix_state in ipairs(states) do
         agg(exporter, ipfix_state, 'packets_received')
         agg(exporter, ipfix_state, 'packets_dropped')
         agg(exporter, ipfix_state, 'packets_ignored')
         agg(exporter, ipfix_state, 'template_packets_transmitted')
         for id, template_state in pairs(ipfix_state.template) do
            templates[id] = templates[id] or {}
            agg(templates[id], template_state, 'packets_processed')
            agg(templates[id], template_state, 'flows_exported')
            agg(templates[id], template_state, 'flow_export_packets')
         end
      end
   end
   -- Arrange RSS group -> IPFIX instance tree
   for exporter, states in pairs(ipfix_states) do
      for _, ipfix_state in ipairs(states) do
         local observation_domain = ipfix_state.observation_domain
         local rss_state = rss_states[observation_domain]
         if not state.rss_group[rss_state.id] then
            state.rss_group[rss_state.id] = {
               id = rss_state.id,
               pid = rss_state.pid,
               queue = collect_queue_state(state.interface, rss_state.id-1),
               exporter = {}
            }
         end
         local rss_group = state.rss_group[rss_state.id]
         if not rss_group.exporter[exporter] then
            rss_group.exporter[exporter] = {
               instance = {}
            }
         end
         local instances = rss_group.exporter[exporter].instance
         instances[ipfix_state.id] = ipfix_state
      end
   end
   -- Convert tables to lists as defined in schema
   local interfaces = state.interface
   state.interface = get_state_grammar('interface').list.new()
   for device, interface in pairs(interfaces) do
      state.interface[device] = interface
   end
   local exporters = state.exporter
   state.exporter = get_state_grammar('exporter').list.new()
   for name, exporter in pairs(exporters) do
      local templates = exporter.template
      exporter.template = get_state_grammar('exporter/template').list.new()
      for id, template in pairs(templates) do
         exporter.template[id] = template
      end
      state.exporter[name] = exporter
   end
   local rss_groups = state.rss_group
   state.rss_group = get_state_grammar('rss-group').list.new()
   for id, rss_group in pairs(rss_groups) do
      local queues = rss_group.queue
      rss_group.queue = get_state_grammar('rss-group/queue').list.new()
      for device, queue in pairs(queues) do
         rss_group.queue[device] = queue
      end
      local exporters = rss_group.exporter
      rss_group.exporter = get_state_grammar('rss-group/exporter').list.new()
      for name, exporter in pairs(exporters) do
         local instances = exporter.instance
         exporter.instance =
            get_state_grammar('rss-group/exporter/instance').list.new()
         for id, instance in pairs(instances) do
            local templates = instance.template
            instance.template =
               get_state_grammar('rss-group/exporter/instance/template').list.new()
            for id, template in pairs(templates) do
               instance.template[id] = template
            end
            exporter.instance[id] = instance
         end
         rss_group.exporter[name] = exporter
      end
      state.rss_group[id] = rss_group
   end
   return {snabbflow_state=state}
end

function get_config_support()
   local s = {
      compute_state_reader = compute_pid_reader,
      process_states = process_states
   }
   for operation, default in pairs(support.generic_schema_config_support) do
      s[operation] = s[operation] or default
   end
   return s
end
