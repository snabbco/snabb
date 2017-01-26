module(..., package.seeall)

local fw     = require("apps.wall.l7fw")
local pcap   = require("apps.pcap.pcap")
local lib    = require("core.lib")
local common = require("program.wall.common")

local long_opts = {
   help = "h",
   links = "l",
   output = "o",
   reject = "r",
   mac = "m",
   ipv4 = "4",
   ipv6 = "6",
   rules_exp = "e",
   rule_file = "f"
}

function run (args)
   local showlinks = false
   local output_file, reject_file
   local local_macaddr, local_ipv4, local_ipv6
   local rule_str

   local opt = {
      o = function (arg)
         output_file = arg
      end,
      r = function (arg)
         reject_file = arg
      end,
      h = function (arg)
         print(require("program.wall.filter.README_inc"))
         main.exit(0)
      end,
      l = function (arg)
         showlinks = true
      end,
      m = function (arg)
         local_macaddr = arg
      end,
      ["4"] = function (arg)
         local_ipv4 = arg
      end,
      ["6"] = function (arg)
         local_ipv6 = arg
      end,
      e = function (arg)
         rule_str = arg
      end,
      f = function (arg)
         rule_str = io.open(arg):read("*a")
      end,
   }

   args = lib.dogetopt(args, opt, "hlo:r:m:4:6:e:f:", long_opts)
   if #args ~= 2 then
      print(require("program.wall.filter.README_inc"))
      main.exit(1)
   end

   assert(rule_str, "Must supply either -e or -f option")
   local rules = assert(load("return " .. rule_str))()

   if type(rules) ~= "table" then
      io.stderr:write("Rules file doesn't define a table\n")
      main.exit(1)
   end

   if not common.inputs[args[1]] then
      io.stderr:write("No such input available: ", args[1], "\n")
      main.exit(1)
   end

   local source_link_name, app = common.inputs[args[1]](args[1], args[2])
   if not source_link_name then
      io.stderr:write(app, "\n")
      main.exit(1)
   end

   local scanner = require("apps.wall.scanner.ndpi"):new()

   local c = config.new()
   config.app(c, "source", unpack(app))
   config.app(c, "l7spy", require("apps.wall.l7spy").L7Spy, { scanner = scanner })

   if not output_file then
      config.app(c, "sink", require("apps.basic.basic_apps").Sink)
   else
      config.app(c, "sink", pcap.PcapWriter, output_file)
   end

   if not reject_file then
      config.app(c, "reject", require("apps.basic.basic_apps").Sink)
   else
      config.app(c, "reject", pcap.PcapWriter, reject_file)
   end

   local fw_config = { scanner = scanner,
                       rules = rules,
                       local_macaddr = local_macaddr,
                       local_ipv4 = local_ipv4,
                       local_ipv6 = local_ipv6 }
   config.app(c, "l7fw", require("apps.wall.l7fw").L7Fw, fw_config)
   config.link(c, "source." .. source_link_name .. " -> l7spy.south")
   config.link(c, "l7spy.north -> l7fw.input")
   config.link(c, "l7fw.output -> sink.input")
   config.link(c, "l7fw.reject -> reject.input")

   engine.configure(c)
   engine.busywait = true
   engine.main({
      report = { showlinks = showlinks },
      done = function ()
         return engine.app_table.source.done
      end
   })
end
