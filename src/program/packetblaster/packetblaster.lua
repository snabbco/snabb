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
local Intel82599 = require("apps.intel.intel_app").Intel82599
local lib = require("core.lib")
local ffi = require("ffi")
local C = ffi.C

local mode

local function show_usage (code)
   if mode == 'replay' then
      print(require("program.packetblaster.replay.README_inc"))
   elseif mode == 'synth' then
      print(require("program.packetblaster.synth.README_inc"))
   elseif mode == 'bounce' then
      print(require("program.packetblaster.bounce.README_inc"))
   else
      print(require("program.packetblaster.README_inc"))
   end
   main.exit(code)
end

local function parse_args (args, short_opts, long_opts)
   local handlers = {}
   local opts = {}
   function handlers.D (arg)
      opts.duration = assert(tonumber(arg), "duration is not a number!")
   end
   function handlers.h (arg)
      show_usage(0)
   end
   function handlers.s (arg) opts.source = arg end
   function handlers.d (arg) opts.destination = arg end
   function handlers.S (arg)
      local sizes = {}
      for size in string.gmatch(arg, "%d+") do
         sizes[#sizes+1] = tonumber(size)
      end
      opts.sizes = sizes
   end
   args = lib.dogetopt(args, handlers, short_opts, long_opts)
   if (mode == 'replay' and #args <= 1) or
      (mode == 'synth' and #args < 1) or
      (mode == 'bounce' and not #args == 3) then
         show_usage(1)
   end
   return opts, args
end

local function report_fn ()
   print("Transmissions (last 1 sec):")
   engine.report_apps()
end

function run (args)
   local opts, c
   mode = table.remove(args, 1)
   if mode == 'replay' then
      c = config.new()
      opts, args = parse_args(args, "hD:r", {help="h", duration="D"})
      local filename = table.remove(args, 1)
      config.app(c, "pcap", PcapReader, filename)
      config.app(c, "loop", basic_apps.Repeater)
      config.app(c, "source", basic_apps.Tee)
      config.link(c, "pcap.output -> loop.input")
      config.link(c, "loop.output -> source.input")
      config_sources(c, args)
   elseif mode == 'synth' then
      c = config.new()
      opts, args = parse_args(args, "hD:rs:d:S:", {help="h", duration="D",
            src="s", dst="d", sizes="S"})
      config.app(c, "source", Synth, { sizes = opts.sizes,
				       src = opts.source,
				       dst = opts.destination })
      config_sources(c, args)
   elseif mode == 'bounce' then
      c = config.new()
      opts, args = parse_args(args, "hD:r", {help="h", duration="D"})
      local filename, nic, bouncer = unpack(args)
      config.app(c, "pcap", PcapReader, filename)
      config.app(c, "loop", basic_apps.Repeater)
      config.app(c, "source", basic_apps.Tee)
      config.link(c, "pcap.output -> loop.input")
      config.link(c, "loop.output -> source.input")
      local nics = config_sources(c, {nic}, {report_rx = true})
      assert(#nics == 1, "Too many nics")
      config.app(c, "bouncer", Intel82599, {
         pciaddr = bouncer
      })
      config.link(c, "bouncer.tx -> bouncer.rx")
      local nic_name = nics[1]
      report_fn = function()
         print("Transmissions and receptions (last 1 sec):")
         engine.app_table[nic_name]:report()
      end
   else
      show_usage(1)
   end

   engine.busywait = true
   intel10g.num_descriptors = 32*1024
   engine.configure(c)
   local fn = function ()
                 print("Transmissions (last 1 sec):")
                 engine.app_table.nic1:report()
              end
   local t = timer.new("report", report_fn, 1e9, 'repeating')
   timer.activate(t)
   if opts.duration then engine.main({duration=opts.duration})
   else                  engine.main() end
end

function config_sources (c, patterns, opts)
   local nic_name = (function()
      local id = 0
      return function()
         id = id + 1
         return id, "nic"..id
      end
   end)()
   local nics = {}
   pci.scan_devices()
   for _,device in ipairs(pci.devices) do
      if is_device_suitable(device, patterns) then
         local id, name = nic_name()
         config.app(c, name, LoadGen, {
            pciaddr = device.pciaddress,
            report_rx = opts and opts.report_rx or false,
         })
         config.link(c, ("source.%d -> %s.input"):format(id, name))
         table.insert(nics, name)
      end
   end
   assert(#nics > 0, "<PCI> matches no suitable devices.")
   return nics
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

