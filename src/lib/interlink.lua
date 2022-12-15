-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

-- INTERLINK: packet queue optimized for inter-process links
--
-- An “interlink” is a thread safe single-producer/single-consumer queue
-- implemented as a ring buffer with a memory layout that is carefully
-- optimized for multi-threaded performance (keyword: “false sharing”). It is
-- represented by a struct allocated in shared memory.
--
-- The processes at each end of an interlink are called the “receiver” and
-- “transmitter” which use disjoint, symmetric subsets of the API on a given
-- queue, as shown below.
--
--    Receiver                   Transmitter
--    ----------                 -------------
--    attach_receiver(name)      attach_transmitter(name)
--    empty(r)                   full(r)
--    extract(r)                 insert(r, p)
--    pull(r)                    push(r)
--    detach_receiver(r, name)   detach_transmitter(r, name)
--
-- I.e., both receiver and transmitter will attach to a queue object they wish
-- to communicate over, and detach once they cease operations.
--
-- Meanwhile, the receiver can extract packets from the queue unless it is
-- empty, while the transmitter can insert new packets into the queue unless
-- it is full.
--
-- Packets inserted by the transmitter only become visible to the receiver once
-- the transmitter calls push. Likewise, queue slots freed from extracting
-- packets only become visible to the transmitter once the receiver calls pull.
--
-- API
-- ----
--
--    attach_receiver(name), attach_transmitter(name)
--       Attaches to and returns a shared memory interlink object by name (a
--       SHM path). If the target name is unavailable (possibly because it is
--       already in use) this operation will block until it becomes available
--       again.
--
--    detach_receiver(r, name), detach_transmitter(r, name)
--       Unmaps interlink r after detaching from the shared queue. Unless the
--       other end is still attached the shared queue is unlinked from its
--       name, and any packets remaining are freed.
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

local CACHELINE = 64 -- XXX - make dynamic
local INT = ffi.sizeof("uint32_t")

-- Based on MCRingBuffer, see
--   http://www.cse.cuhk.edu.hk/%7Epclee/www/pubs/ipdps10.pdf

ffi.cdef([[
   struct interlink {
      uint32_t read, write, size, state[1];
      char pad1[]]..CACHELINE-4*INT..[[];
      uint32_t lwrite, nread, rmask;
      char pad2[]]..CACHELINE-3*INT..[[];
      uint32_t lread, nwrite, wmask;
      char pad3[]]..CACHELINE-3*INT..[[];
      struct packet *packets[?];
   } __attribute__((packed, aligned(]]..CACHELINE..[[)))
]])

-- The life cycle of an interlink is managed using a state machine. This is
-- necessary because we allow receiving and transmitting processes to attach
-- and detach in any order, and even for multiple processes to attempt to
-- attach to the same interlink at the same time.
--
-- Furthermore, more than two processes can attach to and detach from an
-- interlink during its life time. I.e., a new receiver can attach to the queue
-- once the former receiver has detached while the transmitter stays attached
-- throughout, and vice-versa.
--
-- Interlinks can be in one of six states:

local INIT = 0 -- Implicit initial state due to 0 value.
local CONF = 1 -- Queue size is being configured.
local FREE = 2 -- Queue is in free state, ready to attach.
local RXUP = 3 -- Receiver has attached.
local TXUP = 4 -- Transmitter has attached.
local DXUP = 5 -- Both ends have attached.
local DOWN = 6 -- Both ends have detached; must be re-allocated.

-- If at any point both ends have detached from an interlink it stays in the
-- DOWN state until it is deallocated.
--
-- Here are the valid state transitions and when they occur:
--
-- Who      Change          Why
-- ------   -------------   ---------------------------------------------------
-- (any)    none -> INIT    A process creates the queue (initial state).
-- (any)    INIT -> CONF    A process has started configuring the queue.
-- (any)    CONF -> FREE    A process has initialized and configured the queue.
-- recv.    FREE -> RXUP    Receiver attaches to free queue.
-- recv.    TXUP -> DXUP    Receiver attaches to queue with ready transmitter.
-- recv.    DXUP -> TXUP    Receiver detaches from queue.
-- recv.    RXUP -> DOWN    Receiver deallocates queue.
-- trans.   FREE -> TXUP    Transmitter attaches to free queue.
-- trans.   RXUP -> DXUP    Transmitter attaches to queue with ready receiver.
-- trans.   DXUP -> RXUP    Transmitter detaches from queue.
-- trans.   TXUP -> DOWN    Transmitter deallocates queue.
--
-- These state transitions are *PROHIBITED* for important reasons:
--
-- Who      Change      Why *PROHIBITED*
-- ------   ----------- --------------------------------------------------------
-- recv.    INIT->RXUP  Can not attach to uninitialized queue.
-- trans.   INIT->TXUP  Can not attach to uninitialized queue.
-- recv.    CONF->RXUP  Can not attach to unconfigured queue.
-- trans.   CONF->TXUP  Can not attach to unconfigured queue.
-- (any)    FREE->DEAD  Cannot shutdown before having attached.
-- (any)       *->FREE  Cannot transition to FREE except by reallocating.
-- recv.    TXUP->DEAD  Receiver cannot mutate queue after it has detached.
-- recv.    DXUP->RXUP  Receiver cannot detach Transmitter.
-- trans.   RXUP->DEAD  Transmitter cannot mutate queue after it has detached.
-- trans.   DXUP->TXUP  Transmitter cannot detach receiver.
-- (any)    DXUP->DOWN  Cannot shutdown queue while it is in use.
-- (any)    DOWN->*     Cannot transition from DOWN (must create new queue.)

local function attach (name, size, transitions)
   assert(band(size, size-1) == 0, "size is not a power of two")
   local r
   local first_try = true
   waitfor(
      function ()
         -- Create/open the queue.
         r = shm.create(name, "struct interlink", size)
         -- Initialize queue and configure its size
         -- (only one process can set size).
         if sync.cas(r.state, INIT, CONF) then
            r.size = size
            local mask = size - 1
            r.rmask, r.wmask = mask, mask
            assert(sync.cas(r.state, CONF, FREE))
         end
         -- Return if we succeed to attach.
         if transitions(r) then return true end
         -- We failed; handle error and try again.
         shm.unmap(r)
         if first_try then
            print("interlink: waiting for "..name.." to become available...")
            first_try = false
         end
      end
   )
   -- Make sure we agree on the queue size.
   assert(r.size == size, "interlink: queue size mismatch on: "..name)
   -- Ready for action :)
   return r
end

function attach_receiver (name, size)
   return attach(name, size,
                 -- Attach to free queue as receiver (FREE -> RXUP)
                 -- or queue with ready transmitter (TXUP -> DXUP.)
                 function (r) return sync.cas(r.state, FREE, RXUP)
                                  or sync.cas(r.state, TXUP, DXUP) end)
end

function attach_transmitter (name, size)
   return attach(name, size,
                 -- Attach to free queue as transmitter (FREE -> TXUP)
                 -- or queue with ready receiver (RXUP -> DXUP.)
                 function (r) return sync.cas(r.state, FREE, TXUP)
                                  or sync.cas(r.state, RXUP, DXUP) end)
end

local function detach (r, name, reset, shutdown)
   waitfor(
      function ()
         -- Try to detach from queue and leave it for reuse (soft reset).
         if reset(r) then return true
         -- Alternatively, attempt to shutdown and deallocate queue.
         elseif shutdown(r) then
            -- If detach is called by the supervisor (due to an abnormal exit)
            -- the packet module will not be loaded (and there will be no
            -- freelist to put the packets into.)
            while packet and not empty(r) do
               packet.free(extract(r))
            end
            shm.unlink(name)
            return true
         end
      end
   )
   shm.unmap(r)
end

function detach_receiver (r, name)
   detach(r, name,
          -- Reset: detach from queue with active transmitter (DXUP -> TXUP.)
          function (r) return sync.cas(r.state, DXUP, TXUP) end,
          -- Shutdown: deallocate no longer used (RXUP -> DOWN.)
          function (r) return sync.cas(r.state, RXUP, DOWN) end)
end

function detach_transmitter (r, name)
   detach(r, name,
          -- Reset: detach from queue with ready receiver (DXUP -> RXUP.)
          function (r) return sync.cas(r.state, DXUP, RXUP) end,
          -- Shutdown: deallocate no longer used queue (TXUP -> DOWN.)
          function (r) return sync.cas(r.state, TXUP, DOWN) end)
end

-- Queue operations follow below.

local function NEXT (mask, i)
   return band(i + 1, mask)
end

function full (r)
   local after_nwrite = NEXT(r.wmask, r.nwrite)
   if after_nwrite == r.lread then
      if after_nwrite == r.read then
         return true
      end
      r.lread = r.read
   end
end

function insert (r, p)
   r.packets[r.nwrite] = p
   r.nwrite = NEXT(r.wmask, r.nwrite)
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
   r.nread = NEXT(r.rmask, r.nread)
   return p
end

function pull (r)
   -- NB: no need for memory barrier on x86 (see push.)
   r.read = r.nread
end

-- The code below registers an abstract SHM object type with core.shm, and
-- implements the minimum API necessary for programs like snabb top to inspect
-- interlink queues (including a tostring meta-method to describe queue
-- objects.)

shm.register('interlink', getfenv())

function open (name, readonly)
   local r = shm.open(name, "struct interlink", 'read-only', 1)
   local size = r.size
   shm.unmap(r)
   return shm.open(name, "struct interlink", readonly, size)
end

local function describe (r)
   local function queue_fill (r)
      local read, write, size = r.read, r.write, r.size
      return read > write and write + size - read or write - read
   end
   local function status (r)
      return ({
         [INIT] = "being initialized",
         [CONF] = "being configuring",
         [FREE] = "free to attach",
         [RXUP] = "waiting for transmitter",
         [TXUP] = "waiting for receiver",
         [DXUP] = "in active use",
         [DOWN] = "deallocating"
      })[r.state[0]]
   end
   return ("%d/%d (%s)"):format(queue_fill(r), size - 1, status(r))
end

ffi.metatype("struct interlink", {__tostring=describe})
