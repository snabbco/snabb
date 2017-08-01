module(..., package.seeall)

local CSVStatsTimer = require("program.lwaftr.csv_stats").CSVStatsTimer
local RawSocket = require("apps.socket.raw").RawSocket
local LwAftr = require("apps.lwaftr.lwaftr").LwAftr
local lib = require("core.lib")
local lwutil = require("apps.lwaftr.lwutil")
local engine = require("core.app")

local file_exists = lwutil.file_exists

local function check(flag, fmt, ...)
   if not flag then
      io.stderr:write(fmt:format(...), "\n")
      main.exit(1)
   end
end

local function parse_args(args)
   local opts = {
      verbosity = false,
   }
   local conf_file, b4_if, inet_if
   local handlers = {
      v = function ()
         opts.verbosity = true
      end,
      c = function (arg)
         check(file_exists(arg), "no such file '%s'", arg)
         conf_file = arg
      end,
      B = function (arg)
         b4_if = arg
      end,
      I = function (arg)
         inet_if = arg
      end,
      b = function (arg)
         opts.bench_file = arg
         opts.verbosity = true
      end,
      h = function (arg)
         print(require("program.lwaftr.run_nohw.README_inc"))
         main.exit(0)
      end,
      D = function (arg)
         opts.duration = assert(tonumber(arg), "duration must be a number")
      end,
   }
   lib.dogetopt(args, handlers, "b:c:B:I:vhD:", {
      help = "h", conf = "c", verbose = "v",
      ["b4-if"] = "B", ["inet-if"] = "I",
      ["bench-file"] = "b", duration = "D",
   })
   check(conf_file, "no configuration specified (--conf/-c)")
   check(b4_if, "no B4-side interface specified (--b4-if/-B)")
   check(inet_if, "no Internet-side interface specified (--inet-if/-I)")
   return conf_file, b4_if, inet_if, opts
end

function run(parameters)
   local conf_file, b4_if, inet_if, opts = parse_args(parameters)
   local conf = require('apps.lwaftr.conf').load_lwaftr_config(conf_file)
   local c = config.new()
   local device = next(assert(conf.softwire_config.instance))

   -- AFTR
   config.app(c, "aftr", LwAftr, conf)

   -- B4 side interface
   config.app(c, "b4if", RawSocket, b4_if)

   -- Internet interface
   config.app(c, "inet", RawSocket, inet_if)

   -- Connect apps
   config.link(c, "inet.tx -> aftr.v4")
   config.link(c, "b4if.tx -> aftr.v6")
   config.link(c, "aftr.v4 -> inet.rx")
   config.link(c, "aftr.v6 -> b4if.rx")
   config.link(c, "aftr.hairpin_out -> aftr.hairpin_in")

   engine.configure(c)

   if opts.verbosity then
      local csv = CSVStatsTimer:new(opts.bench_file)
      csv:add_app("inet", {"tx", "rx"}, { tx = "IPv4 TX", rx = "IPv4 RX" })
      csv:add_app("b4if", {"tx", "rx"}, { tx = "IPv6 TX", rx = "IPv6 RX" })
      csv:activate()
   end

   if opts.duration then
      engine.main({duration = opts.duration, report = { showlinks = true }})
   else
      engine.main()
   end
end
