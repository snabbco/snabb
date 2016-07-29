-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)
local pci = require("lib.hardware.pci")
local RawSocket = require("apps.socket.raw").RawSocket
local LearningBridge = require("apps.bridge.learning").bridge
local FloodingBridge = require("apps.bridge.flooding").bridge
local vlan = require("apps.vlan.vlan")
local basic_apps = require("apps.basic.basic_apps")
local Synth = require("apps.test.synth").Synth

function configure (c, ports, io)
   local links
   if io and io.pci then
      local device = pci.device_info(io.pci)
      if device and (device.driver == 'apps.intel.intel_app'
                  or device.driver == 'apps.solarflare.solarflare') then
         links = configureVMDq(c, device, ports)
      else
         error("Unknown device: "..io.pci)
      end
   else
      local Switch = "Switch"
      local switch_ports = {}
      for i, port in ipairs(ports) do
         switch_ports[i] = port_name(port)
      end
      local Trunk
      if io and io.iface then
         config.app(c, "TrunkIface", RawSocket, io.iface)
         Trunk = {port = "TrunkIface",
                  input = "TrunkIface.rx",
                  output = "TrunkIface.tx"}
      end
      if io and io.bench then
         config.app(c, "BenchSource", Synth, io.bench)
         config.app(c, "BenchSink", basic_apps.Sink)
         Trunk = {port = "TrunkBench",
                  input = "BenchSink.rx",
                  output = "BenchSource.tx"}
      end
      if Trunk then switch_ports[#switch_ports+1] = Trunk.port end
      if #ports <= 2 then
         config.app(c, Switch, FloodingBridge, {ports = switch_ports})
      else
         config.app(c, Switch, LearningBridge, {ports = switch_ports})
      end
      if Trunk then
         config.link(c, Trunk.output.." -> "..Switch.."."..Trunk.port)
         config.link(c, Switch.."."..Trunk.port.." -> "..Trunk.input)
      end
      links = {}
      for i, port in ipairs(ports) do
         local name = port_name(port)
         local Switch_link = Switch.."."..name
         local Port_tx, Port_rx = Switch_link, Switch_link
         if port.vlan then
            local VlanTag, VlanUntag = name.."_VlanTag", name.."_VlanUntag"
            config.app(c, VlanTag, vlan.Tagger, {tag = port.vlan})
            config.link(c, VlanTag..".output -> "..Port_rx)
            Port_rx = VlanTag..".input"
            config.app(c, VlanUntag, vlan.Untagger, {tag = port.vlan})
            config.link(c, Port_tx.." -> "..VlanUntag..".input")
            Port_tx = VlanUntag..".output"
         end
         links[i] = {input = Port_rx, output = Port_tx}
      end
   end
   return links
end

-- Return name of port in <port_config>.
function port_name (port_config)
   return port_config.port_id:gsub("-", "_")
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
