module(..., package.seeall)

local CSVStatsTimer = require("program.lwaftr.csv_stats").CSVStatsTimer
local ethernet = require("lib.protocol.ethernet")
local RawSocket = require("apps.socket.raw").RawSocket
local LwAftr = require("apps.lwaftr.lwaftr").LwAftr
local lib = require("core.lib")
local S = require("syscall")

local function check(flag, fmt, ...)
   if not flag then
      io.stderr:write(fmt:format(...), "\n")
      main.exit(1)
   end
end

local function file_exists(path)
   local stat = S.stat(path)
   return stat and stat.isreg
end

local function parse_args(args)
   local verbosity = 0
   local conf_file, b4_if, inet_if
   local bench_file = 'bench.csv'
   local handlers = {
      v = function ()
         verbosity = verbosity + 1
      end;
      c = function (arg)
         check(file_exists(arg), "no such file '%s'", arg)
         conf_file = arg
      end;
      B = function (arg)
         b4_if = arg
      end;
      I = function (arg)
         inet_if = arg
      end;
      ["bench-file"] = function (arg)
         bench_file = arg
      end;
      h = function (arg)
         print(require("program.lwaftr.run_nohw.README_inc"))
         main.exit(0)
      end;
   }
   lib.dogetopt(args, handlers, "b:c:B:I:vh", {
      help = "h", conf = "c", verbose = "v",
      ["b4-if"] = "B", ["inet-if"] = "I",
      bench_file = 0,
   })
   check(conf_file, "no configuration specified (--conf/-c)")
   check(b4_if, "no B4-side interface specified (--b4-if/-B)")
   check(inet_if, "no Internet-side interface specified (--inet-if/-I)")
   return verbosity, conf_file, b4_if, inet_if, bench_file
end


function run(parameters)
   local verbosity, conf_file, b4_if, inet_if, bench_file = parse_args(parameters)
   local c = config.new()

   -- AFTR
   config.app(c, "aftr", LwAftr, conf_file)

   -- B4 side interface
   config.app(c, "b4if", RawSocket, b4_if)

   -- Internet interface
   config.app(c, "inet", RawSocket, inet_if)

   -- Connect apps
   config.link(c, "inet.tx -> aftr.v4")
   config.link(c, "b4if.tx -> aftr.v6")
   config.link(c, "aftr.v4 -> inet.rx")
   config.link(c, "aftr.v6 -> b4if.rx")

   if verbosity >= 1 then
      local csv = CSVStatsTimer.new(csv_file)
      csv:add_app("inet", {"tx", "rx"}, { tx = "IPv4 TX", rx = "IPv4 RX" })
      csv:add_app("tob4", {"tx", "rx"}, { tx = "IPv6 TX", rx = "IPv6 RX" })
      csv:activate()

      if verbosity >= 2 then
         timer.activate(timer.new("report", function ()
            app.report_apps()
         end, 1e9, "repeating"))
      end
   end

   engine.configure(c)
   engine.main {
      report = {
         showlinks = true;
      }
   }
end
