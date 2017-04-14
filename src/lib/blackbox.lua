-- blackbox.lua -- detailed event recorder ("black box flight recorder")
-- 
-- ### Overview
-- 
-- The "black box" of a Snabb process is like the flight recorder in
-- an airplane: a detailed event log that can be inspected for
-- investigting problems such as crashes or performance degradations
-- that occur in a production environment.
--
-- The black box logs entries by fork()ing a child process to produce
-- and log the message. This makes the complete state of the process
-- available for inspection without delaying the parent process (which
-- can continue to process traffic). This is intended to enable
-- logging detailed information that could be computationally
-- expensive to produce without without impacting the latency of
-- traffic processing. For example:
--
-- * Print full LuaJIT trace dumps.
-- * Print a profiler report.
-- * Scan the heap and summarize all allocated memory.
--
-- ### API
--
-- record(event_name, func):
--   Run 'func' in a fork()ed child process and capture its output
--   (calls to print() and io.write()) in a named black box record.

module(..., package.seeall)

local S = require("syscall")

function record (event_name, func)
   local ppid = S.getpid()
   if S.fork() ~= 0 then return end -- parent process
   local box = ("/var/run/snabb/%d/black.box"):format(ppid)
   -- Redirect standard output to the blackbox file
   io.output(assert(io.open(box, 'a')))
   func()
   os.exit(0)
end

function selftest ()
   print("selftest: blackbox")
   print("measuring simple app network throughput with recording intervals")
   local function configure ()
      local c = config.new()
      config.app(c, "source", require("apps.basic.basic_apps").Source)
      config.app(c, "sink",   require("apps.basic.basic_apps").Sink)
      config.link(c, "source.output->sink.input")
      engine.configure(config.new())
      engine.configure(c)
   end
   -- Setup timer
   local interval, deadline
   local timerhook = function ()
      if interval then
         deadline = deadline or engine.now()
         if engine.now() >= deadline then
            record("record",
                   function ()
                      -- Burn some cycles
                      for i = 1, 1e7 do end
                      -- Print a message (to the black box log)
                      for i = 1, 1000 do io.write("test record\n") end
                      -- Hang around long enough to be a potential
                      -- nuisance for copy-on-write memory.
                      require("ffi").C.usleep(100)
            end)
            deadline = deadline + interval
         end
      end
   end
   timer.activate(timer.new('blackbox', timerhook, 1e6, 'repeating'))
   -- Warmup
   configure()
   engine.main({duration=0.001})
   -- Run for one second with no recording
   configure()
   io.write("(none) ") io.flush()
   engine.main({duration=1})
   io.flush()
   -- Run with recording at different intervals (seconds)
   for _, secs in ipairs({0.5, 0.25, 0.1, 0.05, 0.01, 0.005, 0.001}) do
      interval = secs
      deadline = nil
      io.write(("%.3fs "):format(secs)) io.flush()
      engine.main({duration=1})
   end
   print("selftest ok")
end

