-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

-- INTERLINK: packet queue optimized for inter-process links
--
-- An “interlink” is a thread safe single-producer/single-consumer queue
-- implemented as a ring buffer with a memory layout that is carefully
-- optimized for multi-threaded performance (keyword: “false sharing”).
--
-- The processes at each end of an interlink will both call `new' and `free' in
-- order to create/delete the shared ring buffer. Beyond this, the processes
-- that share an interlink each must restrict themselves to calling either
--
--    full  insert  push          (transmitting)
--
-- or
--
--    empty  extract  pull        (receiving)
--
-- on the queue.
--
-- I.e., the transmitting process `insert's new packets into the queue while it
-- is not `full', and makes new packets visible to the receiving process by
-- calling `push'. The receiving process, on the other hand, `extract's packets
-- while the queue is not `empty', and notifies the transmitting process of
-- newly available slots by calling `pull'.
--
--    new(name)
--       Attaches to and returns a shared memory interlink object by name (a
--       SHM path). If the target name is unavailable (possibly because it is
--       already in use), this operation will block until it becomes available
--       again.
--
--    free(r, name)
--       Unmaps interlink r and unlinks it from its name. If other end has
--       already freed the interlink, any packets remaining in the queue are
--       freed.
--
--    full(r) / empty(r)
--       Return true if the interlink r is full / empty.
--
--    insert(r, p) / extract(r)
--       Insert a packet p into / extract a packet from interlink r. Must not
--       be called if r is full / empty.
--
--    push(r) / pull(r)
--       Makes subsequent calls to full / empty reflect updates to the queue
--       caused by insert / extract.

local shm = require("core.shm")
local ffi = require("ffi")
local band = require("bit").band
local waitfor = require("core.lib").waitfor
local sync = require("core.sync")

local SIZE = link.max + 1
local CACHELINE = 64 -- XXX - make dynamic
local INT = ffi.sizeof("int")

assert(band(SIZE, SIZE-1) == 0, "SIZE is not a power of two")

-- Based on MCRingBuffer, see
--   http://www.cse.cuhk.edu.hk/%7Epclee/www/pubs/ipdps10.pdf

ffi.cdef([[ struct interlink {
   int read, write, state[1];
   char pad1[]]..CACHELINE-3*INT..[[];
   int lwrite, nread;
   char pad2[]]..CACHELINE-2*INT..[[];
   int lread, nwrite;
   char pad3[]]..CACHELINE-2*INT..[[];
   struct packet *packets[]]..SIZE..[[];
} __attribute__((packed, aligned(]]..CACHELINE..[[)))]])

-- The life cycle of an interlink is managed using a state machine. This is
-- necessary because we allow receiving and transmitting processes to attach
-- and detach in any order, and even for multiple processes to attempt to
-- attach to the same interlink at the same time.
--
-- Interlinks can be in one of three states:

local FREE = 0 -- Implicit initial state due to 0 value.
local UP   = 1 -- Other end has attached.
local DOWN = 2 -- Either end has detached; must be re-allocated.

-- Once either end detaches from an interlink it stays in the DOWN state
-- until it is deallocated.
--
-- Here are the valid state transitions and when they occur:
--
-- Change          When
-- -------------   --------------------------------------------------------
-- none -> FREE    a process has successfully created the queue.
-- FREE -> UP      another process has attached to the queue.
-- UP   -> DOWN    either process has detached from the queue.
-- FREE -> DOWN    creator detached before any other process could attach.
-- DOWN -> none    the process that detaches last frees the queue (and the
--                 packets remaining in it).

function new (name)
   local ok, r
   local first_try = true
   waitfor(
      function ()
         -- First we try to create the queue.
         ok, r = pcall(shm.create, name, "struct interlink")
         if ok then return true end
         -- If that failed then we try to open (attach to) it.
         ok, r = pcall(shm.open, name, "struct interlink")
         if ok and sync.cas(r.state, FREE, UP) then return true end
         -- We failed; handle error and try again.
         if ok then shm.unmap(r) end
         if first_try then
            print("interlink: waiting for "..name.." to become available...")
            first_try = false
         end
      end
   )
   return r
end

function free (r, name)
   if sync.cas(r.state, FREE, DOWN)
   or not sync.cas(r.state, UP, DOWN) then
      while not empty(r) do
         packet.free(extract(r))
      end
      shm.unlink(name)
   end
   shm.unmap(r)
end

local function NEXT (i)
   return band(i + 1, link.max)
end

function full (r)
   local after_nwrite = NEXT(r.nwrite)
   if after_nwrite == r.lread then
      if after_nwrite == r.read then
         return true
      end
      r.lread = r.read
   end
end

function insert (r, p)
   r.packets[r.nwrite] = p
   r.nwrite = NEXT(r.nwrite)
end

function push (r)
   -- NB: no need for memory barrier on x86 because of TSO.
   r.write = r.nwrite
end

function empty (r)
   if r.nread == r.lwrite then
      if r.nread == r.write then
         return true
      end
      r.lwrite = r.write
   end
end

function extract (r)
   local p = r.packets[r.nread]
   r.nread = NEXT(r.nread)
   return p
end

function pull (r)
   -- NB: no need for memory barrier on x86 (see push.)
   r.read = r.nread
end
