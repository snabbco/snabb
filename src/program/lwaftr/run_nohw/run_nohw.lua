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
   local handlers = {
      v = function ()
         verbosity = verbosity + 1
      end;
      c = function (arg)
         check(arg, "argument to '--conf' not specified")
         check(file_exists(arg), "no such file '%s'", arg)
         conf_file = arg
      end;
      B = function (arg)
         check(arg, "argument to '--b4-if' not specified")
         b4_if = arg
      end;
      I = function (arg)
         check(arg, "argument to '--inet-if' not specified")
         inet_if = arg
      end;
      h = function (arg)
		print(require("program.lwaftr.run_nohw.README_inc"))
		main.exit(0)
	  end;
   }
   lib.dogetopt(args, handlers, "b:c:B:I:vh", {
      help = "h", conf = "c", verbose = "v",
      ["b4-if"] = "B", ["inet-if"] = "I",
   })
   check(conf_file, "no configuration specified (--conf/-c)")
   check(b4_if, "no B4-side interface specified (--b4-if/-B)")
   check(inet_if, "no Internet-side interface specified (--inet-if/-I)")
   return verbosity, conf_file, b4_if, inet_if
end


function run(parameters)
   local verbosity, conf_file, b4_if, inet_if = parse_args(parameters)
   local c = config.new()

   -- AFTR
   config.app(c, "aftr", LwAftr, conf_file)

   -- B4 side interface
   config.app(c, "b4if", RawSocket, b4_if)

   -- Internet interface
   config.app(c, "inet", RawSocket, inet_if)

   -- Connect apps
   config.link(c, "inet.output -> aftr.v4")
   config.link(c, "b4if.output -> aftr.v6")
   config.link(c, "aftr.v4 -> inet.input")
   config.link(c, "aftr.v6 -> b4if.input")

   if verbosity >= 1 then
      local csv = CSVStatsTimer.new()
      csv:add_app("inet", {"output", "input"}, { output = "IPv4 OUTPUT", input = "IPv4 INPUT" })
      csv:add_app("tob4", {"output", "input"}, { output = "IPv6 OUTPUT", input = "IPv6 INPUT" })
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
