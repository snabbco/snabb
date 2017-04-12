module(..., package.seeall)

local fw     = require("apps.wall.l7fw")
local pcap   = require("apps.pcap.pcap")
local now    = require("core.app").now
local lib    = require("core.lib")
local link   = require("core.link")
local numa   = require("lib.numa")
local common = require("program.wall.common")

local long_opts = {
   help = "h",
   output = "o",
   reject = "r",
   mac = "m",
   ipv4 = "4",
   ipv6 = "6",
   log = "l",
   duration = "D",
   cpu = 1,
   ["print-report"] = "p",
   ["rules-exp"] = "e",
   ["rule-file"] = "f"
}

function run (args)
   local report = false
   local logging = "off"
   local cpu, duration
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
      p = function (arg)
         report = true
      end,
      m = function (arg)
         local_macaddr = arg
      end,
      l = function (arg)
         logging = arg
      end,
      D = function (arg)
         duration = tonumber(arg)
      end,
      ["cpu"] = function (arg)
         cpu = assert(tonumber(arg), "--cpu expects a number")
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
         local file = io.open(arg)
         assert(file, "could not open rules file")
         rule_str = file:read("*a")
      end
   }

   args = lib.dogetopt(args, opt, "hpl:D:o:r:m:4:6:e:f:", long_opts)
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
                       local_ipv6 = local_ipv6,
                       logging = logging }
   config.app(c, "l7fw", require("apps.wall.l7fw").L7Fw, fw_config)
   config.link(c, "source." .. source_link_name .. " -> l7spy.south")
   config.link(c, "l7spy.north -> l7fw.input")
   config.link(c, "l7fw.output -> sink.input")
   config.link(c, "l7fw.reject -> reject.input")

   local done
   if not duration then
      done = function ()
         return engine.app_table.source.done
      end
   end

   if cpu then numa.bind_to_cpu(cpu) end

   local start_time = now()

   engine.configure(c)
   engine.busywait = true
   engine.main({
      report = { showapps = report },
      duration = duration,
      done = done
   })

   if report then
      local end_time = now()
      local fw = engine.app_table.l7fw
      local input_link = fw.input.input
      local stats = link.stats(input_link)
      print("Firewall stats:")
      print(string.format("bytes: %s packets: %s bps: %s",
                          lib.comma_value(stats.rxbytes),
                          lib.comma_value(stats.rxpackets),
                          lib.comma_value((stats.rxbytes * 8) / (end_time - start_time))))
   end
end
