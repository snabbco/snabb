-- Multiprocess benchmarks
-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local S = require("syscall")
local pmu = require("lib.pmu")
local lib = require("core.lib")

local shm = require("core.shm")
local band = require("bit").band

-- Ring benchmark:
-- See how quickly packets are cycled through a ring of processes.
--
-- Each process copies packets from its input to its output link. Each
-- link is populated with an initial "burst" of packets.

local cache_line_size = 64

-- ff (FastForward) link

-- John Giacomoni, Tipp Moseley, and Manish Vachharajani. 2008.
-- FastForward for efficient pipeline parallelism:
-- a cache-optimized concurrent lock-free queue. In Proceedings of the
-- 13th ACM SIGPLAN Symposium on Principles and practice of parallel
-- programming (PPoPP '08). ACM, New York, NY, USA, 43-52.
-- DOI=http://dx.doi.org/10.1145/1345206.1345215

local ff_size = 256

ffi.cdef([[
/*
 * Put read and write members on private cache lines,
 * which are assumed to be 64 bytes long.
 */
struct ff_link
{
    struct packet *packets[$];
    uint32_t read  __attribute__((aligned(64)));
    uint32_t write __attribute__((aligned(64)));
};
]], ff_size)

function ff_new (name)
   local r = shm.map("links/"..name, "struct ff_link")
   -- try to verify expected alignment
   local p = ffi.new("struct ff_link *[1]")
   p[0] = r
   local n = ffi.cast("uintptr_t", p[0])
   local mask = cache_line_size - 1
   assert(band(n, mask) == 0, "struct ff_link not 64-bit aligned")
   assert(band(ffi.offsetof("struct ff_link", "read"), mask) == 0,
	  "read field not 64-bit aligned within struct ff_link")
   assert(band(ffi.offsetof("struct ff_link", "write"), mask) == 0,
	  "write field not 64-bit aligned within struct ff_link")
   return r
end

function ff_empty (r)
   return r.packets[r.read] == nil
end

function ff_available (r)
   return r.packets[r.write] == nil
end

function ff_full (r)
   return r.packets[r.write] ~= nil
end

function ff_maybe_rx (r)
   local p = r.packets[r.read];
   if p ~= nil then
      r.packets[r.read] = nil;
      r.read = band(r.read + 1, ff_size - 1)
   end
   return p
end

function ff_maybe_tx (r, p)
   if r.packets[r.write] ~= nil then
      return nil
   else
      r.packets[r.write] = p
      r.write = band(r.write + 1, ff_size - 1)
      return p
   end
end


-- mc (MCRingBuffer) link

-- Patrick P. C. Lee, Tian Bu, and Girish Chandranmenon. 2009.
-- A lock-free, cache-efficient shared ring buffer for multi-core architectures.
-- In Proceedings of the 5th ACM/IEEE Symposium on Architectures for Networking
-- and Communications Systems (ANCS '09). ACM, New York, NY, USA, 78-79.
-- DOI=http://dx.doi.org/10.1145/1882486.1882508

local mc_size = 256
local mc_batch_size = 10

ffi.cdef([[
struct mc_link
{
    struct packet *packets[$];
    uint32_t read __attribute__((aligned(64)));
    uint32_t write;
    uint32_t local_write __attribute__((aligned(64)));
    uint32_t next_read;
    uint32_t read_batch;
    uint32_t local_read __attribute__((aligned(64)));
    uint32_t next_write;
    uint32_t write_batch;
};
]], mc_size)

function mc_new (name)
   local r = shm.map("links/"..name, "struct mc_link")
   local p = ffi.new("struct mc_link *[1]")
   p[0] = r
   local n = ffi.cast("uintptr_t", p[0])
   local mask = cache_line_size - 1
   assert(band(n, mask) == 0, "struct mc_link not 64-bit aligned")
   assert(band(ffi.offsetof("struct mc_link", "read"), mask) == 0,
	  "read field not 64-byte aligned within struct mc_link")
   assert(band(ffi.offsetof("struct mc_link", "local_write"), mask) == 0,
	  "local_write field not 64-byte aligned within struct mc_link")
   assert(band(ffi.offsetof("struct mc_link", "local_read"), mask) == 0,
	  "local_read field not 64-byte aligned within struct mc_link")

   return r
end

function mc_maybe_rx (r)
   if r.next_read == r.local_write then
      if r.next_read == r.write then
	 return nil
      end
      r.local_write = r.write
   end
   local p = r.packets[r.next_read]
   r.next_read = band(r.next_read + 1, mc_size -1)
   r.read_batch = r.read_batch + 1
   if r.read_batch >= mc_batch_size then
      r.read = r.next_read
      r.read_batch = 0
   end
   return p
end

function mc_maybe_tx (r, p)
   local after_next = band(r.next_write + 1, mc_size - 1)
   if after_next == r.local_read then
      if after_next == r.read then
	 return nil
      end
      r.local_read = r.read
   end
   r.packets[r.next_write] = p
   r.next_write = after_next
   r.write_batch = r.write_batch + 1
   if r.write_batch >= mc_batch_size then
      r.write = r.next_write
      r.write_batch = 0
   end
   return p
end


function make_links(mode, nlinks, npackets)
   local links = {}

   if mode == "basic" then
      for i = 0, nlinks - 1 do
	 links[i] = link.new(tostring(i))
	 for j = 1, npackets do
	    link.transmit(links[i], packet.allocate())
	 end
      end
   elseif mode == "ff" then
      for i = 0, nlinks - 1 do
	 links[i] = ff_new(tostring(i))
	 for j = 1, npackets do
	    local p = ff_maybe_tx(links[i], packet.allocate())
	    if p == nil then
	       error("can't transmit packet while priming ff links")
	    end
	 end
      end
   elseif mode == "mc" then
      for i = 0, nlinks - 1 do
	 links[i] = mc_new(tostring(i))
	 for j = 1, npackets do
	    local p = mc_maybe_tx(links[i], packet.allocate())
	    if p == nil then
	       error("can't transmit packet while priming mc links")
	    end
	 end
      end
   else
      error("unknown mode " .. mode)
   end

   return links
end

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
   local leftover = lib.dogetopt(args, opt, "hm:n:p:b:e:r:w:", long_opts)
   if #leftover > 0 then usage () end
   -- Print summary of configuration
   print("Benchmark configuration:")
   for k, v in pairs(c) do
      print(("%12s: %s"):format(k,v))
   end

   links = make_links(c.mode, c.processes, c.burst)
   
   -- Create per-process counters
   local counters = ffi.cast("uint64_t *",
                             memory.dma_alloc(c.processes*ffi.sizeof("uint64_t")))
   -- Start child processes
   local start = C.get_time_ns()
   for i = 0, c.processes-1 do
      if S.fork() == 0 then
         -- Child <i> has affinity to CPU core <i>
         S.sched_setaffinity(0, i)
         -- terminate when parent does
         S.prctl("set_pdeathsig", "hup")
         local input = links[i]
         local output = links[(i+1) % c.processes]
         -- Setup PMU if configured
         local pmuctr
         if c.pmuevents and i == 0 then
            -- Enable PMU if requires and only for process #0.
            pmu.setup({c.pmuevents})
            pmuctr = pmu.new_counter_set()
            pmu.switch_to(pmuctr)
         end
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
	 elseif c.mode == "ff" then
            local acc = ffi.new("uint8_t[1]")
	    while counters[i] < c.packets do
	       local p = ff_maybe_rx(input)
	       if p ~= nil then
                  -- Read some packet data
                  for j = 0, c.readbytes do
                     acc[0] = acc[0] + p.data[j]
                  end
                  -- Write some packet data
                  for j = 0, c.writebytes do
                     p.data[j] = i
                  end

		  local sent = nil
		  repeat
		     sent = ff_maybe_tx(output, p)
		  until sent ~= nil
		  counters[i] = counters[i] + 1
	       end
	       core.lib.compiler_barrier()
	    end
	 elseif c.mode == "mc" then
            local acc = ffi.new("uint8_t[1]")
	    while counters[i] < c.packets do
	       local p = mc_maybe_rx(input)
	       if p ~= nil then
                  -- Read some packet data
                  for j = 0, c.readbytes do
                     acc[0] = acc[0] + p.data[j]
                  end
                  -- Write some packet data
                  for j = 0, c.writebytes do
                     p.data[j] = i
                  end

		  local sent = nil
		  repeat
		     sent = mc_maybe_tx(output, p)
		  until sent ~= nil
		  counters[i] = counters[i] + 1
	       end
	       core.lib.compiler_barrier()
	    end
         else
            print("mode not recognized: " .. c.mode)
            os.exit(1)
         end
         if pmuctr then
            C.usleep(1e4) -- XXX print after parent
            print("PMU report for child #0:")
            pmu.switch_to(nil)
            pmu.report(pmu.to_table(pmuctr), {packet=c.packets})
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
   -- XXX Sleep for a short while before terminating.
   -- This allows the children to print a report before the parent
   -- exiting causes them to die. (It would be better to synchronize
   -- this properly.)
   C.usleep(1e5)
end
