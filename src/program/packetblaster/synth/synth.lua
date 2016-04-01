-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local engine    = require("core.app")
local config    = require("core.config")
local timer     = require("core.timer")
local pci       = require("lib.hardware.pci")
local intel10g  = require("apps.intel.intel10g")
local main      = require("core.main")
local Synth     = require("apps.test.synth").Synth
local LoadGen   = require("apps.intel.loadgen").LoadGen
local lib = require("core.lib")
local ffi = require("ffi")

local packetblaster = require("program.packetblaster.packetblaster")
local usage = require("program.packetblaster.synth.README_inc")

local long_opts = {
   duration     = "D",
   help         = "h",
   src          = "s",
   dst          = "d",
   sizes        = "S"
}

function run (args)
   local opt = {}
   local duration
   local c = config.new()
   function opt.D (arg) 
      duration = assert(tonumber(arg), "duration is not a number!")  
   end
   function opt.h (arg)
      print(usage)
      main.exit(1)
   end

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
     src = source, dst = destination })

   local patterns = args
   local nics = 0
   pci.scan_devices()
   for _,device in ipairs(pci.devices) do
      if packetblaster.is_device_suitable(device, patterns) then
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
   local t = timer.new("report", packetblaster.report, 1e9, 'repeating')
   timer.activate(t)
   if duration then engine.main({duration=duration})
   else             engine.main() end
end
