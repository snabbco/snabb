module(..., package.seeall)

local lib = require("core.lib")
local nfvconfig = require("program.snabbnfv.nfvconfig")
local usage = require("program.snabbnfv.traffic.README_inc")
local ffi = require("ffi")
local C = ffi.C
local timer = require("core.timer")
local pci = require("lib.hardware.pci")

local long_opts = {
   benchmark     = "B",
   help          = "h",
   ["link-report-interval"] = "k",
   ["load-report-interval"] = "l",
   ["debug-report-interval"] = "D",
   ["long-help"] = "H"
}

function run (args)
   local opt = {}
   local benchpackets
   local linkreportinterval = 60
   local loadreportinterval = 1
   local debugreportinterval = 600
   function opt.B (arg) benchpackets = tonumber(arg)      end
   function opt.h (arg) print(short_usage()) main.exit(1) end
   function opt.H (arg) print(long_usage())  main.exit(1) end
   function opt.k (arg) linkreportinterval = tonumber(arg) end
   function opt.l (arg) loadreportinterval = tonumber(arg) end
   function opt.D (arg) debugreportinterval = tonumber(arg) end
   args = lib.dogetopt(args, opt, "hHB:k:l:D:", long_opts)
   if #args == 3 then
      local pciaddr, confpath, sockpath = unpack(args)
      local ok, info = pcall(pci.device_info, pciaddr)
      if not ok then
         print("Error: device not found " .. pciaddr)
         os.exit(1)
      end
      if not info.driver then
         print("Error: no driver for device " .. pciaddr)
         os.exit(1)
      end
      if loadreportinterval > 0 then
	 local t = timer.new("nfvloadreport", engine.report_load, loadreportinterval*1e9, 'repeating')
	 timer.activate(t)
      end
      if linkreportinterval > 0 then
	 local t = timer.new("nfvlinkreport", engine.report_links, linkreportinterval*1e9, 'repeating')
	 timer.activate(t)
      end
      if debugreportinterval > 0 then
	 local t = timer.new("nfvdebugreport", engine.report_apps, debugreportinterval*1e9, 'repeating')
	 timer.activate(t)
      end
      if benchpackets then
	 print("snabbnfv traffic starting (benchmark mode)")
	 bench(pciaddr, confpath, sockpath, benchpackets)
      else
	 print("snabbnfv traffic starting")
	 traffic(pciaddr, confpath, sockpath)
      end
   else
      print("Wrong number of arguments: " .. tonumber(#args))
      print()
      print(short_usage())
      main.exit(1)
   end
end

function short_usage () return (usage:gsub("%s*CONFIG FILE FORMAT:.*", "")) end
function long_usage () return usage end

-- Run in real traffic mode.
function traffic (pciaddr, confpath, sockpath)
   engine.log = true
   local mtime = 0
   while true do
      local mtime2 = C.stat_mtime(confpath)
      if mtime2 ~= mtime then
	 print("Loading " .. confpath)
	 engine.configure(nfvconfig.load(confpath, pciaddr, sockpath))
	 mtime = mtime2
      end
      engine.main({duration=1, no_report=true})
      -- Flush buffered log messages every 1s
      io.flush()
   end
end

-- Run in benchmark mode.
function bench (pciaddr, confpath, sockpath, npackets)
   npackets = tonumber(npackets)
   local ports = dofile(confpath)
   local nic = (nfvconfig.port_name(ports[1])).."_NIC"
   engine.log = true
   engine.Hz = false

   print("Loading " .. confpath)
   engine.configure(nfvconfig.load(confpath, pciaddr, sockpath))

   -- From designs/nfv
   local start, packets, bytes = 0, 0, 0
   local done = function ()
      if start == 0 and engine.app_table[nic].input.rx.stats.rxpackets > 0 then
         -- started receiving, record time and packet count
         packets = engine.app_table[nic].input.rx.stats.rxpackets
         bytes = engine.app_table[nic].input.rx.stats.rxbytes
         start = C.get_monotonic_time()
         if os.getenv("NFV_PROF") then
            require("jit.p").start(os.getenv("NFV_PROF"), os.getenv("NFV_PROF_FILE"))
         else
            print("No LuaJIT profiling enabled ($NFV_PROF unset).")
         end
         if os.getenv("NFV_DUMP") then
            require("jit.dump").start(os.getenv("NFV_DUMP"), os.getenv("NFV_DUMP_FILE"))
            main.dumping = true
         else
            print("No LuaJIT dump enabled ($NFV_DUMP unset).")
         end
      end
      return engine.app_table[nic].input.rx.stats.rxpackets - packets >= npackets
   end

   engine.main({done = done, no_report = true})
   local finish = C.get_monotonic_time()

   local runtime = finish - start
   packets = engine.app_table[nic].input.rx.stats.rxpackets - packets
   bytes = engine.app_table[nic].input.rx.stats.rxbytes - bytes
   engine.report()
   print()
   print(("Processed %.1f million packets in %.2f seconds (%d bytes; %.2f Gbps)"):format(packets / 1e6, runtime, bytes, bytes * 8.0 / 1e9 / runtime))
   print(("Made %s breaths: %.2f packets per breath; %.2fus per breath"):format(lib.comma_value(engine.breaths), packets / engine.breaths, runtime / engine.breaths * 1e6))
   print(("Rate(Mpps):\t%.3f"):format(packets / runtime / 1e6))
   require("jit.p").stop()
end

