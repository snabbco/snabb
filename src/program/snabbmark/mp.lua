-- Multiprocess benchmarks
-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local S = require("syscall")
local pmu = require("lib.pmu")
local lib = require("core.lib")

-- Ring benchmark:
-- See how quickly packets are cycled through a ring of processes.
--
-- Each process copies packets from its input to its output link. Each
-- link is populated with an initial "burst" of packets.
function mp_ring (args)
   local function usage ()
      print(require("program.snabbmark.README_mp_inc"))
      os.exit(1)
   end
   local long_opts = {
      help = "h",
      mode = "m",
      processes = "n",
      packets = "p",
      burst = "b",
      events = "e",
      read = "r",
      write = "w"
   }
   local c = {
      mode = "basic",
      processes = 2,
      packets = 100e6,
      burst = 100,
      pmuevents = false,
      readbytes = 0,
      writebytes = 0
   }
   local opt = {}
   function opt.m (arg) c.mode = arg end
   function opt.n (arg) c.processes = tonumber(arg) end
   function opt.p (arg) c.packets = tonumber(arg) end
   function opt.b (arg) c.burst = tonumber(arg) end
   function opt.e (arg) c.pmuevents = arg end
   function opt.r (arg) c.readbytes = tonumber(arg) end
   function opt.w (arg) c.writebytes = tonumber(arg) end
   function opt.h (arg) usage() end
   local leftover = lib.dogetopt(args, opt, "hn:p:b:e:r:w:", long_opts)
   if #leftover > 0 then usage () end
   -- Print summary of configuration
   print("Benchmark configuration:")
   for k, v in pairs(c) do
      print(("%12s: %s"):format(k,v))
   end
   links = {}
   -- Create links to connect the processes in a loop
   for i = 0, c.processes-1 do
      links[i] = link.new(tostring(i))
      for j = 1, c.burst do
         link.transmit(links[i], packet.allocate())
      end
   end
   -- Create per-process counters
   local counters = ffi.cast("uint64_t *",
                             memory.dma_alloc(c.processes*ffi.sizeof("uint64_t")))
   -- Start child processes
   if c.pmuevents then error("PMU support NYI") end
   local start = C.get_time_ns()
   for i = 0, c.processes-1 do
      if S.fork() == 0 then
         -- Child <i> has affinity to CPU core <i>
         S.sched_setaffinity(0, i)
         -- terminate when parent does
         S.prctl("set_pdeathsig", "hup")
         local input = links[i]
         local output = links[(i+1) % c.processes]
         if c.mode == "basic" then
            -- Simple reference implementation in idiomatic Lua.
            local acc = ffi.new("uint8_t[1]")
            while counters[i] < c.packets do
               if not link.empty(input) and not link.full(output) then
                  local p = link.receive(input)
                  -- Read some packet data
                  for j = 0, c.readbytes do
                     acc[0] = acc[0] + p.data[j]
                  end
                  -- Write some packet data
                  for j = 0, c.writebytes do
                     p.data[j] = i
                  end
                  link.transmit(output, p)
                  counters[i] = counters[i] + 1
               end
               -- Sync registers with memory
               core.lib.compiler_barrier()
            end
         else
            print("mode not recognized: " .. c.mode)
            os.exit(1)
         end
         os.exit(0)
      end
   end
   -- Spin until enough packets have been processed
   while counters[0] < c.packets do
      core.lib.compiler_barrier()
   end
   local finish = C.get_time_ns()
   local seconds = tonumber(finish-start)/1e9
   local packets = tonumber(counters[0])
   print(("%7.2f Mpps ring throughput per process"):format(packets/seconds/1e6))
end
