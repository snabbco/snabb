module(..., package.seeall)

local engine    = require("core.app")
local config    = require("core.config")
local timer     = require("core.timer")
local pci       = require("lib.hardware.pci")
local intel10g  = require("apps.intel.intel10g")
local intel_app = require("apps.intel.intel_app")
local basic_apps = require("apps.basic.basic_apps")
local main      = require("core.main")
local PcapReader= require("apps.pcap.pcap").PcapReader
local Synth     = require("apps.test.synth").Synth
local LoadGen   = require("apps.intel.loadgen").LoadGen
local lib = require("core.lib")
local ffi = require("ffi")
local C = ffi.C

local usage = require("program.packetblaster.README_inc")
local usage_replay = require("program.packetblaster.replay.README_inc")
local usage_synth = require("program.packetblaster.synth.README_inc")

local long_opts = {
   duration     = "D",
   help         = "h",
   source       = "s",
   destination  = "d",
   sizes        = "S"
}

function run (args)
   local opt = {}
   local mode = table.remove(args, 1)
   local duration
   local c = config.new()
   function opt.D (arg) 
      duration = assert(tonumber(arg), "duration is not a number!")  
   end
   function opt.h (arg)
      if mode == 'replay' then print(usage_replay)
      elseif mode == 'synth' then print(usage_synth)
      else print(usage) end
      main.exit(1)
   end
   if mode == 'replay' and #args > 1 then
      args = lib.dogetopt(args, opt, "hD:", long_opts)
      local filename = table.remove(args, 1)
      config.app(c, "pcap", PcapReader, filename)
      config.app(c, "loop", basic_apps.Repeater)
      config.app(c, "source", basic_apps.Tee)
      config.link(c, "pcap.output -> loop.input")
      config.link(c, "loop.output -> source.input")
   elseif mode == 'synth' and #args >= 1 then
      local source
      local destination
      local sizes
      function opt.s (arg) source = arg end
      function opt.d (arg) destination = arg end
      function opt.S (arg)
         sizes = {}
	 for size in string.gmatch(arg, "%d+") do
	    sizes[#sizes+1] = tonumber(size)
	 end
      end
      
      args = lib.dogetopt(args, opt, "hD:s:d:S:", long_opts)
      config.app(c, "source", Synth, { sizes = sizes,
				       src = source,
				       dst = destination })
   else
      opt.h()
   end
   local patterns = args
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
   assert(nics > 0, "<PCI> matches no suitable devices.")
   engine.busywait = true
   intel10g.num_descriptors = 32*1024
   engine.configure(c)
   local fn = function ()
                 print("Transmissions (last 1 sec):")
                 engine.report_apps()
              end
   local t = timer.new("report", fn, 1e9, 'repeating')
   timer.activate(t)
   if duration then engine.main({duration=duration})
   else             engine.main() end
end

function is_device_suitable (pcidev, patterns)
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

