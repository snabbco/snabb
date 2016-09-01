-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)
local pci = require("lib.hardware.pci")
local RawSocket = require("apps.socket.raw").RawSocket
local LearningBridge = require("apps.bridge.learning").bridge
local FloodingBridge = require("apps.bridge.flooding").bridge
local vlan = require("apps.vlan.vlan")
local MacFilter = require("program.snabbnfv.apps.macfilter").MacFilter
local Hash = require("program.snabbnfv.apps.hash").Hash
local basic_apps = require("apps.basic.basic_apps")
local Synth = require("apps.test.synth").Synth

function configure (c, ports, io)
   local trunk, links, queues, features
   if io and io.pci then
      local device = pci.device_info(io.pci)
      if device then
         if (device.driver == 'apps.intel.intel_app' and no_queues(ports))
             or device.driver == 'apps.solarflare.solarflare' then
            queues = configureVMDq(c, device, ports)
            features = {vlan=true, mac_address=true}
         elseif device.driver == 'apps.intel.intel_mp'
                or device.driver == 'apps.intel.intel_app' then
            links = configureRSS(c, device, ports)
            features = {}
         end
      else
         error("Unknown device: "..io.pci)
      end
   elseif io.iface then
      config.app(c, "TrunkIface", RawSocket, io.iface)
      trunk = {port = "TrunkIface",
               input = "TrunkIface.rx",
               output = "TrunkIface.tx"}
   elseif io.bench then
      config.app(c, "BenchSource", Synth, io.bench)
      config.app(c, "BenchSink", basic_apps.Sink)
      trunk = {port = "TrunkBench",
               input = "BenchSink.rx",
               output = "BenchSource.tx"}
   end
   if not links and not queues then
      queues = port_queues(ports)
   end
   if not links then
      local Switch = "Switch"
      local switch_ports = {}
      local ports = queues or ports
      if #ports == 1 then
         if trunk then
            links = {trunk}
         end
      else
         for i, port in ipairs(queues or ports) do
            switch_ports[i] = port_name(port)
         end
         if trunk then switch_ports[#switch_ports+1] = trunk.port end
         if #ports <= 2 then
            config.app(c, Switch, FloodingBridge, {ports = switch_ports})
         else
            config.app(c, Switch, LearningBridge, {ports = switch_ports})
         end
         if trunk then
            config.link(c, trunk.output.." -> "..Switch.."."..trunk.port)
            config.link(c, Switch.."."..trunk.port.." -> "..trunk.input)
         end
         links = {}
         for i, port in ipairs(ports) do
            local Switch_link = Switch.."."..port_name(port)
            links[i] = {input = Switch_link, output = Switch_link}
         end
         features.mac_address = true
      end
   end
   if not features.vlan then
      for i, port in ipairs(ports or queues) do
         if port.vlan then
            local Port_tx, Port_rx = links[i].input, links[i].output
            local name = port_name(port)
            local VlanTag, VlanUntag = name.."_VlanTag", name.."_VlanUntag"
            config.app(c, VlanTag, vlan.Tagger, {tag = port.vlan})
            config.link(c, VlanTag..".output -> "..Port_rx)
            Port_rx = VlanTag..".input"
            config.app(c, VlanUntag, vlan.Untagger, {tag = port.vlan})
            config.link(c, Port_tx.." -> "..VlanUntag..".input")
            Port_tx = VlanUntag..".output"
            links[i].input, links[i].output = Port_rx, Port_tx
         end
      end
      features.vlan = true
   end
   if not features.mac_address then
      for i, port in ipairs(ports or queues) do
         if port.mac_address then
            local Port_rx = links[i].input, links[i].output
            local Mac = port_name(port).."_MacFilter"
            config.app(c, Mac, MacFilter, port.mac_address)
            config.link(c, Mac..".south -> "..Port_rx)
            Port_rx = Mac..".north"
            config.link(c, Port_tx.." -> "..Mac..".south")
            Port_tx = Mac..".north"
            links[i].input, links[i].output = Port_rx, Port_tx
         end
      end
      features.mac_address = true
   end
   if queues then
      local dest_ports = {}
      for i, dest in ipairs(queues) do
         dest_ports[dest.port_id] = {
            input = links[i].input,
            outputs = {}
         }
         if #dest.queues > 1 then
            local Queues = "Queues_"..dest.port_id
            config.app(c, Queues, Hash)
            config.app(c, links[i].output.." -> "..Queues..".input")
            for _, port in ipairs(dest.queues) do
               assert(dest.queue, "Port does not define queue: "..dest.port_id)
               local queue = Queues.."."..dest.queue
               dest_ports[dest.port_id].outputs[port.port_id] = queue
            end
         else
            dest_ports[dest.port_id].outputs[port[1].port_id] = links[i].output
         end
      end
      links = {}
      for _, port in ipairs(ports) do
         local dest = port_dest(port)
         links[#links+1] = {input = dest_ports[dest][port.port_id],
                            output = dest_ports[dest].output}
      end
   end
   return links
end

-- Return name of port in <port_config>.
function port_name (port_config)
   return port_config.port_id:gsub("-", "_")
end

function port_dest (port_config)
   return (port_config.vlan or "null").."/"..(port_config.mac_address or "null")
end

function port_queues (ports)
   local dest_ports = {}
   for _, port in ipairs(ports) do
      local queue_for = port_dest(port)
      if not dest_ports[queue_for] then dest_ports[queue_for] = {} end
      table.insert(dest_ports[queue_for], port)
   end
   local queues = {}
   for dest, ports in pairs(dest_ports) do
      queues[#queues+1] = {port_id = dest, queues = ports}
   end
   return queues
end

function configureVMDq (c, device, ports)
   local links = {}
   for i, port in ipairs(ports) do
      local name = port_name(port)
      local NIC = name.."_NIC"
      local vmdq = true
      if not port.mac_address then
         if #ports ~= 1 then
            error("multiple ports defined but promiscuous mode requested for port: "..name)
         end
         vmdq = false
      end
      config.app(c, NIC, require(device.driver).driver,
                 {pciaddr = device.pciaddress,
                  vmdq = vmdq,
                  macaddr = port.mac_address,
                  vlan = port.vlan})
      links[i] = {input = NIC..".rx", output = NIC..".tx"}
   end
   return links
end

function no_queues (ports)
   local queues = false
   for _, port in ipairs(ports) do
      if port.queue then queues = true break end
   end
   return not queues
end

function configureRSS (c, device, ports)
   local links = {}
   for i, port in ipairs(ports) do
      local NIC = port_name(port).."_NIC"
      config.app(c, NIC, require("apps.intel.intel_mp").driver,
                 {pciaddr = device.pciaddress,
                  rxq = port.queue,
                  txq = port.queue})
      links[i] = {input = NIC..".rx", output = NIC..".tx"}
   end
   return links
end
