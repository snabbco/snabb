module(..., package.seeall)

local app = require("core.app")
local config = require("core.config")
local lib = require("core.lib")
local setup = require("program.snabb_lwaftr.setup")

function show_usage(code)
   print(require("program.snabb_lwaftr.check.README_inc"))
   main.exit(code)
end

function parse_args(args)
   local handlers = {}
   function handlers.h() show_usage(0) end
   args = lib.dogetopt(args, handlers, "h", { help="h" })
   if #args ~= 5 then show_usage(1) end
   return unpack(args)
end

function run(args)
   local conf_file, inv4_pcap, inv6_pcap, outv4_pcap, outv6_pcap =
      parse_args(args)

   local conf = require('apps.lwaftr.conf').load_lwaftr_config(conf_file)

   local c = config.new()
   setup.load_check(c, conf, inv4_pcap, inv6_pcap, outv4_pcap, outv6_pcap)
   app.configure(c)
   app.main({duration=0.10})
   print("done")
end
