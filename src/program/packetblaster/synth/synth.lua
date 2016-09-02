-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local config    = require("core.config")
local main      = require("core.main")
local Synth     = require("apps.test.synth").Synth
local lib       = require("core.lib")

local packetblaster = require("program.packetblaster.packetblaster")

local long_opts = {
   duration     = "D",
   help         = "h",
   src          = "s",
   dst          = "d",
   sizes        = "S"
}

local function show_usage (code)
   print(require("program.packetblaster.synth.README_inc"))
   main.exit(code)
end

function run (args)
   local opt = {}
   local duration
   local c = config.new()
   function opt.D (arg)
      duration = assert(tonumber(arg), "duration is not a number!")
   end
   function opt.h ()
      show_usage(0)
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
   if not (sizes or source or destination) then show_usage(1) end
   config.app(c, "source", Synth, { sizes = sizes,
      src = source, dst = destination })
   packetblaster.run_loadgen(c, args, duration)
end
