-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local engine    = require("core.app")
local timer     = require("core.timer")
local lib       = require("core.lib")
local pci       = require("lib.hardware.pci")
local LoadGen   = require("apps.intel_mp.loadgen").LoadGen
local Intel82599 = require("apps.intel_mp.intel_mp").Intel82599
local connectx = require("apps.mellanox.connectx")

local function is_device_suitable (pcidev, patterns)
   if not pcidev.usable then
      return false
   end
   if #patterns == 0 then
      return true
   end
   for _, pattern in ipairs(patterns) do
      if pci.qualified(pcidev.pciaddress):gmatch(pattern)() then
         return true
      end
   end
end

local function configure_nic (c, n, device, use_loadgen)
   if device.driver:match('intel') then
      configure_intel_nic(c, n, device, use_loadgen)
   elseif device.driver:match('connectx') then
      configure_connectx_nic(c, n, device, use_loadgen)
   else
      error("Unsupported driver: "..device.driver)
   end
end

function configure_intel_nic (c, n, device, use_loadgen)
   local name = "nic"..n
   if use_loadgen then
      config.app(c, name, LoadGen, device.pciaddress)
   else
      config.app(c, name, Intel82599, {pciaddr = device.pciaddress})
   end
   config.link(c, "source."..name.."->"..name..".input")
end

function configure_connectx_nic (c, n, device, use_loadgen)
   local name = "nic"..n
   local numq = (use_loadgen and 16) or 1
   local queues = {}
   for q=0, numq-1 do
      local ioname = name.."_q"..q
      config.app(c, ioname, connectx.IO, {
         pciaddress = device.pciaddress,
         queue = q,
         packetblaster = use_loadgen
      })
      config.link(c, "source."..ioname.."->"..ioname..".input")
      table.insert(queues, {id=q})
   end
   config.app(c, name, connectx.ConnectX, {
      pciaddress = device.pciaddress,
      sendq_size = 4096,
      queues = queues,
      sync_stats_interval = 0.01
   })
end

function run_loadgen (c, patterns, opts)
   assert(type(opts) == "table")
   local use_loadgen = opts.loop == nil or opts.loop
   local nics = 0
   pci.scan_devices()
   for _,device in ipairs(pci.devices) do
      if is_device_suitable(device, patterns) then
         nics = nics + 1
         configure_nic(c, nics, device, use_loadgen)
      end
   end
   assert(nics > 0, "<PCI> matches no suitable devices.")
   engine.busywait = true
   engine.configure(c)

   local report = {}
   if use_loadgen then
      local fn = function ()
         print("Transmissions (last 1 sec):")
         engine.report_apps()
      end
      local t = timer.new("report", fn, 1e9, 'repeating')
      timer.activate(t)
   else
      report = {showlinks = true}
   end

   if opts.duration then engine.main({duration=opts.duration, report=report})
   else             engine.main() end
end

local function show_usage(exit_code)
   print(require("program.packetblaster.README_inc"))
   main.exit(exit_code)
end

function run(args)
   if #args == 0 then show_usage(1) end
   local command = string.gsub(table.remove(args, 1), "-", "_")
   local modname = ("program.packetblaster.%s.%s"):format(command, command)
   if not lib.have_module(modname) then
      show_usage(1)
   end
   require(modname).run(args)
end
