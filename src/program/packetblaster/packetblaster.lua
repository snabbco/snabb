-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local lib = require("core.lib")
local pci = require("lib.hardware.pci")
local LoadGen   = require("apps.intel.loadgen").LoadGen

local function is_device_suitable (pcidev, patterns)
   if not pcidev.usable or pcidev.driver ~= 'apps.intel.intel_app' then
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

function config_loadgen(c, patterns)
  local nics = 0
  pci.scan_devices()
  for _,device in ipairs(pci.devices) do
    if is_device_suitable(device, patterns) then
      nics = nics + 1
      local name = "nic"..nics
      config.app(c, name, LoadGen, device.pciaddress)
      config.link(c, "source."..tostring(nics).."->"..name..".input")
    end
  end
  return nics
end

local function show_usage(exit_code)
  print(require("program.packetblaster.README_inc"))
  main.exit(exit_code)
end

function report ()
  print("Transmissions (last 1 sec):")
  engine.report_apps()
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
