module(..., package.seeall)

local config = require("core.config")
local lib = require("core.lib")
local lwconf = require('apps.lwaftr.conf')
local setup = require("program.lwaftr.setup")

local long_opts = {
   duration="D",
   help="h",
   ["on-a-stick"] = 0,
}

function show_usage(code)
   print(require("program.lwaftr.soaktest.README_inc"))
   main.exit(code)
end

function parse_args (args)
   local handlers = {}
   local opts = {}
   function handlers.h() show_usage(0) end
   function handlers.D (arg)
      opts.duration = assert(tonumber(arg), "Duration must be a number")
   end
   handlers["on-a-stick"] = function ()
      opts["on-a-stick"] = true
   end
   args = lib.dogetopt(args, handlers, "D:h", long_opts)
   if #args ~= 3 then print("Wrong number of arguments: "..#args) show_usage(1) end
   if not opts.duration then opts.duration = 0.10 end
   return opts, args
end

function run (args)
   local opts, args = parse_args(args)
   local conf_file, inv4_pcap, inv6_pcap = unpack(args)

   local load_soak_test = opts["on-a-stick"] and setup.load_soak_test_on_a_stick
                                             or  setup.load_soak_test
   local c = config.new()
   local conf = lwconf.load_lwaftr_config(conf_file)
   load_soak_test(c, conf, inv4_pcap, inv6_pcap)

   engine.configure(c)
   engine.main({duration=opts.duration})

   print("done")
end
