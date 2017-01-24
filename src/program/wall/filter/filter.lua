module(..., package.seeall)

local fw     = require("apps.wall.l7fw")
local pcap   = require("apps.pcap.pcap")
local lib    = require("core.lib")
local common = require("program.wall.common")

local long_opts = {
   help = "h",
   links = "l",
   output = "o",
}

function run (args)
   local output_file, showlinks = nil, false
   local opt = {
      o = function (arg)
         output_file = arg
      end,
      h = function (arg)
         print(require("program.wall.filter.README_inc"))
         main.exit(0)
      end,
      l = function (arg)
         showlinks = true
      end
   }

   args = lib.dogetopt(args, opt, "hlo:", long_opts)
   if #args ~= 3 then
      print("TODO instructions")
      main.exit(1)
   end

   local rule_str = io.open(args[1]):read("*a")
   local rules = assert(load("return " .. rule_str))()

   if type(rules) ~= "table" then
      io.stderr:write("Rules file doesn't define a table\n")
      main.exit(1)
   end

   if not common.inputs[args[2]] then
      io.stderr:write("No such input available: ", args[1], "\n")
      main.exit(1)
   end

   local source_link_name, app = common.inputs[args[2]](args[2], args[3])
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
   config.app(c, "l7fw", require("apps.wall.l7fw").L7Fw, { scanner = scanner, rules = rules })
   config.link(c, "source." .. source_link_name .. " -> l7spy.south")
   config.link(c, "l7spy.north -> l7fw.input")
   config.link(c, "l7fw.output -> sink.input")

   engine.configure(c)
   engine.busywait = true
   engine.main({
      report = { showlinks = showlinks },
      done = function ()
         return engine.app_table.source.done
      end
   })
end
