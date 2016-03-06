-- Multiprocess benchmarks
-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local S = require("syscall")

-- Ring benchmark:
-- See how quickly packets are cycled through a ring of processes.
--
-- Each process copies packets from its input to its output link. Each
-- link is populated with an initial "burst" of packets.
function mp_ring (nprocesses, totalpackets, burstpackets)
   nprocesses = tonumber(nprocesses)
   totalpackets = tonumber(totalpackets)
   burstpackets = tonumber(burstpackets)
   links = {}
   -- Create links to connect the processes in a loop
   for i = 0, nprocesses-1 do
      links[i] = link.new(tostring(i))
      for j = 1, burstpackets do
         link.transmit(links[i], packet.allocate())
      end
   end
   -- Create per-process counters
   local counters = ffi.cast("uint64_t *",
                             memory.dma_alloc(nprocesses*ffi.sizeof("uint64_t")))
   -- Start child processes
   local start = C.get_time_ns()
   for i = 0, nprocesses-1 do
      if S.fork() == 0 then
         -- Child <i> has affinity to CPU core <i>
         S.sched_setaffinity(0, i)
         -- terminate when parent does
         S.prctl("set_pdeathsig", "hup")
         local input = links[i]
         local output = links[(i+1) % nprocesses]
         while counters[i] < totalpackets do
            if not link.empty(input) and not link.full(output) then
               link.transmit(output, link.receive(input))
               counters[i] = counters[i] + 1
            end
            -- Sync registers with memory
            core.lib.compiler_barrier()
         end
         os.exit(0)
      end
   end
   -- Spin until enough packets have been processed
   while counters[0] < totalpackets do
      core.lib.compiler_barrier()
   end
   local finish = C.get_time_ns()
   local seconds = tonumber(finish-start)/1e9
   local packets = tonumber(counters[0])
   print(("%7.2f Mpps ring throughput per process"):format(packets/seconds/1e6))
end
