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
   sizes        = "S",
}

local function show_usage (code)
   print(require("program.packetblaster.synth.README_inc"))
   main.exit(code)
end

function run (args)
   local c = config.new()
   local handlers = {}
   local opts = {}
   function handlers.D (arg)
      opts.duration = assert(tonumber(arg), "duration is not a number!")
   end
   function handlers.h ()
      show_usage(0)
   end

   local source
   local destination
   local sizes
   function handlers.s (arg) source = arg end
   function handlers.d (arg) destination = arg end
   function handlers.S (arg)
      sizes = {}
      for size in string.gmatch(arg, "%d+") do
         sizes[#sizes+1] = tonumber(size)
      end
   end

   args = lib.dogetopt(args, handlers, "hD:s:d:S:", long_opts)
   config.app(c, "source", Synth, { sizes = sizes,
      src = source, dst = destination })
   packetblaster.run_loadgen(c, args, opts)
end
