-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)
local pci = require("lib.hardware.pci")
local FloodingBridge = require("apps.bridge.flooding").bridge
local SoftIO = require("program.snabbnfv.apps.emu").SoftIO
local vlan = require("apps.vlan.vlan")
local Synth = require("apps.test.synth").Synth
local Sink = require("apps.basic.basic_apps").Sink

IO = {}

-- Macro app, first of its kind.
-- Usage:
--   config.app("VqNIC", IO, {pciaddr="03:00.1", macaddr="00:00:..."})
--   config.app("RssNIC", IO, {pciaddr="04:00.0", txq=1, rxq=1})
--   config.app("SoftIO", IO, {vlan=42})
--   config.app("BenchIO", IO, {bench={sizes={60}}})
function IO:configure (c, name, conf)
   if conf.pciaddr then
      local device = assert(pci.device_info(conf.pciaddr),
                            "Unknown device: "..conf.pciaddr)
      if ((device.driver == 'apps.intel.intel_app'
           and not (conf.txq or conf.rxq))
          or device.driver == 'apps.solarflare.solarflare')
      then
         config.app(c, name, require(device.driver).driver, conf)
      elseif (device.driver == 'apps.intel.intel_mp'
              or device.driver == 'apps.intel.intel_app')
      then
         config.app(c, name, require("apps.intel.intel_mp").driver, conf)
      else
         error("Unsupported device: "..device.model)
      end
   else
      local Bridge = "_SoftIOBridge"..(conf.hub or 0)
      if not c.apps[Bridge] then
         config.app(c, Bridge, FloodingBridge, {ports={}})
      end
      local port_exists = false
      for _, port in ipairs(c.apps[Bridge].arg.ports) do
         port_exists = (port == name)
      end
      if not port_exists then
         table.insert(c.apps[Bridge].arg.ports, name)
      end
      if conf.bench then
         config.app(c, name, Synth, conf.bench)
         config.link(c, name..".output -> "..Bridge.."."..name)
         local BenchSink = "_Sink_"..name
         config.app(c, BenchSink, Sink)
         config.link(c, Bridge.."."..name.." -> "..BenchSink..".rx")
      else
         config.app(c, name, SoftIO, conf)
         if conf.vlan then
            local VT, VU = Bridge.."_VlanTagger_for_", Bridge.."_VlanUnTagger_for_"
            config.app(c, VT..name, conf.vlan)
            config.link(c, name..".trunk -> "..VT..name..".input")
            config.link(c, VT..name..".output -> "..Bridge.."."..name)
            config.app(c, VU..name, conf.vlan)
            config.link(c, Bridge.."."..name.." -> "..VU..name..".input")
            config.link(c, VU..name..".output -> "..name..".trunk")
         else
            config.link(c, name..".trunk -> "..Bridge.."."..name)
            config.link(c, Bridge.."."..name.." -> "..name..".trunk")
         end
      end
   end
end
