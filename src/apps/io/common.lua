-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- config.app(c, "IO", IO, {type="pci", device="01:00.0",
--                          queues={a = {...}, ...}})

module(..., package.seeall)

-- Maps type names to implementations
local type = {}


IO = {
   config = {
      type = {default='emu'},
      device = {},
      queues = {required=true}
   }
}

function IO:configure (c, name, conf)
   local impl = assert(type[conf.type], "Unknown IO type: "..conf.type)
   impl(c, name, conf.device, conf.queues)
end


function type.emu (c, name, device, queues)
   local FloodingBridge = require("apps.bridge.flooding").bridge
   local Emu = require("apps.io.emu").Emu
   local bridge = device or name
   local ports, mod = {}, 1
   for name, queue in pairs(queues) do
      table.insert(ports, name)
      if queue.hash then
         mod = math.max(queue.hash, mod)
      end
   end
   config.app(c, name, FloodingBridge, {ports=ports})
   for name, queue in pairs(queues) do
      config.app(c, name, Emu, queue)
      config.link(c, name..".trunk -> "..bridge.."."..name)
      config.link(c, bridge.."."..name.." -> "..name..".trunk")
   end
end


-- Maps PCI driver to implementations
local driver = {}

function type.pci (c, name, device, queues)
   local pci = require("lib.hardware.pci")
   local impl = assert(driver[pci.device_info(device).driver],
                       "Unsupported PCI device: "..device)
   impl(c, name, device, queues)
end

driver['apps.intel.intel_app'] = function (c, name, device, queues)
   local Intel82599 = require("apps.intel.intel_app").Intel82599
   local nqueues, vmdq = 0, false
   for _ in pairs(queues) do
      nqueues = nqueues + 1
      if nqueues > 1 then vmdq = true; break end
   end
   for name, queue in pairs(queues) do
      if not queue.macaddr and vmdq then
         error(io..": multiple ports defined, "..
               "but promiscuous mode requested for queue: "..name)
      end
      queue.pciaddr = device
      queue.vmdq = vmdq or (not not queue.macaddr)
      config.app(c, name, Intel82599, queue)
   end
end


function selftest ()
   require("apps.io.emu")
   local c = config.new()
   config.app(c, "IO", IO,
              {queues = {a = {macaddr="60:50:40:40:20:10", hash=1},
                         b = {macaddr="60:50:40:40:20:10", hash=2}}})
   engine.configure(c)
   engine.report_apps()
   engine.report_links()
end
