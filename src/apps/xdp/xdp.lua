-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local S = require("syscall")
local ffi = require("ffi")
local bpf = require("apps.xdp.bpf")
local pf  = require("apps.xdp.pf_ebpf_codegen")
local lib = require("core.lib")
local bits = lib.bits
local band, bor, rshift, tobit = bit.band, bit.bor, bit.rshift, bit.tobit

-- ---- XDP driver for Snabb --------------------------------------------

-- This is a Snabb driver for Linux AF_XDP[1][2] sockets. The XDP kernel
-- interface presents an ABI/API combination similar to what a hardware NIC
-- usually provides: a way to attach to hardware queues, and a set of
-- descriptor rings for each queue used to enqueue and dequeue packet memory
-- buffers.
--
-- Like with hardware NICs, XDP imposes us with constraints on the kind of
-- memory buffers we can enqueue onto its descriptor rings. Instead of DMA
-- memory required to drive hardware NICs, XDP requires us to register a
-- special kind of memory called UMEM to use with an AF_XDP socket. Only
-- buffers in the UMEM registered with a given socket can be used for I/O with
-- that socket!
--
-- To consolidate this and other constraints (see "UMEM allocation" below) with
-- Snabb's packet memory architecture this driver allocates a single contiguous
-- memory region used as UMEM for all of the process' AF_XDP sockets, and
-- replaces the memory allocation routine dma_alloc in core.memory with its own
-- UMEM allocator. Hence, the packet freelist will be filled with UMEM memory
-- buffers used for all packet allocations.
--
--    snabb_enable_xdp()
--
--       To use the XDP app, "Snabb XDP mode" must be enabled by calling this
--       function. Calling this function replaces Snabb's native memory
--       allocator with the UMEM allocator.
--
--       The caller must ensure that no packets have been allocated via
--       packet.allocate() prior to calling this function.
--
--       CAVEATS:
--
--          * Memory allocated by the UMEM allocator can not be used with DMA
--            drivers: using the XDP app precludes the use of Snabb's native
--            hardware drivers.
--
--          * Memory allocated by the UMEM allocator can not be shared with
--            other Snabb processes in the same process group: using
--            snabb_enable_xdp precludes the use of Interlink apps
--            (apps.interlink).
--
--          * UMEM chunks can not be larger than the page size (4096 bytes).
--            This AD_XDP limitation plus the way Snabb implements packet
--            buffer shifting operations limits the effective MTU: the MTU of
--            the XDP app is limited to 3,582 bytes. See XDP:create_xsk().
--
-- The only means by which an AF_XDP socket can receive packets from a device
-- is by attaching an eBPF XDP program to the Linux interface. The XDP app
-- assembles a minimal BPF program to route packets from device queues to XDP
-- sockets. See XDP:initialize_xdp.
--
-- References:
-- [1] https://www.kernel.org/doc/html/v5.3/networking/af_xdp.html
-- [2] The Linux kernel source repository


-- ---- UMEM allocation -------------------------------------------------

-- Must maintain invariants: chunk size must be <= page size and UMEM must be
-- aligned to page size.

local page_size = S.getpagesize()
local chunk_size = page_size
local num_chunks = 200000
local umem_backing, umem, umem_size, umem_used

-- UMEM allocator: multiple UMEM chunks must be allocated to fit a full packet.
-- However, AF_XDP sockets will only ever see the first of the chunks that make
-- up a packet. The extra (two) UMEM chunks are effectively unused by the
-- socket (but used by Snabb to ensure that packets can actually use
-- packet.max_payload bytes of payload).
-- See core.packet, "XDP rings", XDP:create_xsk().
local function umem_alloc (size, align)
   -- NB: align parameter ignored as we align to chunk_size
   assert(align <= chunk_size)
   assert(umem_used + size <= umem_size,
          "Out of packet buffer memory. Increase num_chunks?")
   local chunk = umem + umem_used
   umem_used = lib.align(umem_used + size, chunk_size)
   return chunk
end

-- Convert from pointer to relative UMEM offset.
local function to_umem (ptr)
   return ffi.cast("uintptr_t", ptr) - ffi.cast("uintptr_t", umem)
end

-- Convert relative UMEM offset to pointer.
local function from_umem (offset)
   return umem + offset
end

local snabb_xdp_enabled = false
function snabb_enable_xdp (opt)
   opt = opt or {}
   if opt.num_chunks then
      num_chunks = math.ceil(assert(tonumber(opt.num_chunks),
                                    "num_chunks must be a number"))
   end
   -- Allocate UMEM
   umem_size = chunk_size * num_chunks
   umem_backing = ffi.new("char[?]", umem_size + page_size)
   umem = ffi.cast("char*", lib.align(ffi.cast("uintptr_t", umem_backing), page_size))
   umem_used = 0
   -- Hot-swap core.memory.dma_alloc
   require("core.memory").dma_alloc = umem_alloc
   snabb_xdp_enabled = true
end


-- ---- FFI types -------------------------------------------------------

local xdp_umem_reg_t = ffi.typeof[[
   struct {
      void *   addr; /* Start of packet data area */
      uint64_t len;  /* Length of packet data area */
      uint32_t chunk_size;
      uint32_t headroom;
      uint32_t flags; /* Not available in 4.19 */
   } __attribute__((packed))]]

local sockaddr_xdp_t = ffi.typeof[[
   struct {
      uint16_t family;
      uint16_t flags;
      uint32_t ifindex;
      uint32_t queue_id;
      uint32_t shared_umem_fd;
   } __attribute__((packed))]]

local xdp_ring_offset_t = ffi.typeof[[
   struct {
      uint64_t producer;
      uint64_t consumer;
      uint64_t desc;
      uint64_t flags; /* Not available in 4.19 */
   } __attribute__((packed))]]

local xdp_ring_offset_noflags_t = ffi.typeof[[
   struct {
      uint64_t producer;
      uint64_t consumer;
      uint64_t desc;
   } __attribute__((packed))]]

local xdp_mmap_offsets_templ = [[
   struct {
      $ rx,
        tx,
        fr,  /* Fill */
        cr;  /* Completion */
   } __attribute__((packed))]]
local xdp_mmap_offsets_noflags_t =
   ffi.typeof(xdp_mmap_offsets_templ, xdp_ring_offset_noflags_t)
local xdp_mmap_offsets_t =
   ffi.typeof(xdp_mmap_offsets_templ, xdp_ring_offset_t)

local xdp_ring_t = ffi.typeof[[
   struct {
      char *map;
      size_t maplen;
      uint32_t *producer, *consumer, *flags;
      void *desc;
      uint32_t write, read;
   }]]

local xdp_desc_t = ffi.typeof[[
   struct {
      uint64_t addr;
      uint32_t len;
      uint32_t options;
   } __attribute__((packed))]]
local xdp_desc_ptr_t = ffi.typeof("$ *", xdp_desc_t)

local netlink_set_link_xdp_request_t = ffi.typeof[[
   struct {
     struct { /* nlmsghdr */
       uint32_t nlmsg_len;	/* Length of message including header */
       uint16_t nlmsg_type;	/* Message content */
       uint16_t nlmsg_flags;	/* Additional flags */
       uint32_t nlmsg_seq;	/* Sequence number */
       uint32_t nlmsg_pid;	/* Sending process port ID */
     } nh;
     struct { /* ifinfomsg */
       unsigned char ifi_family;
       unsigned char __ifi_pad;
       unsigned short ifi_type;	/* ARPHRD_* */
       int ifi_index;		/* Link index	*/
       unsigned ifi_flags;	/* IFF_* flags	*/
       unsigned ifi_change;	/* IFF_* change mask */
     } ifinfo;
     struct { /* nlattr */
       uint16_t nla_len;
       uint16_t nla_type;
     } xdp;
     struct { /* nlattr */
       uint16_t nla_len;
       uint16_t nla_type;
       int32_t fd;
     } xdp_fd;
   }__attribute__((packed))]]


-- ---- XDP rings -------------------------------------------------------

-- Ring operations for the single-producer single-consumer rings used for I/O
-- with AF_XDP sockets (xdp_ring_t). This is is a blend between an
-- "Array + two unmasked indices"[1] and MCRingBuffer[2] implementation.
--
-- Only the "Array + two unmasked indices" half of the implementation is
-- actually exposed by the kernel via the pointers to shared consumer/producer
-- fields (see xdp_ring_t, XDP:xdp_map_ring()). The MCRingBuffer portion is
-- added by userspace (us) to optimize our CPU cache footprint.
--
-- Each AF_XDP socket has two rings (rx, tx) and each UMEM has two rings
-- (fr - fill ring, cr - completion ring). This XDP driver registers a new UMEM
-- for each socket so that each socket effectively has four rings
-- (rx, tx, fr, cr).
--
-- For the Linux kernel to be able to fill the rx ring we need to provide it
-- UMEM chunks via the fill ring (fr). Chunks used by us to send packets via
-- the tx ring are returned by the kernel back to the userspace application via
-- the completion ring (cr).
--
-- It is important to note that XDP rings operate on chunks: the addr field
-- of xdp_desc_t points *into* a chunk, and its len field is, from the kernel’s
-- perspective, bounded to the end of that chunk. See "UMEM allocation" and
-- XDP:create_xsk() for how this affects Snabb.
--
-- NB: Snabb packet payloads are preceded by a two byte length field, so we
-- have to account for this overhead when retrieving packets from XDP
-- descriptor rings. See receive(r) below and XDP:create_xsk().
--
-- References:
-- [1] https://www.snellman.net/blog/archive/2016-12-13-ring-buffers/
-- [2] https://www.cse.cuhk.edu.hk/~pclee/www/pubs/ancs09poster.pdf

local xdp_ring_ndesc = 2048 -- Number of descriptors in ring.

local function mask  (i)    return band(i, xdp_ring_ndesc - 1) end
local function inc   (i)    return tobit(i + 1) end
local function full1 (r, w) return tobit(w - r) == xdp_ring_ndesc end

function full (r)
   if full1(r.read, r.write) then
      if full1(r.consumer[0], r.write) then
         return true
      end
      r.read = r.consumer[0]
   end
end

function transmit (r, p)
   local desc = ffi.cast(xdp_desc_ptr_t, r.desc)
   local idx = mask(r.write)
   desc[idx].addr = to_umem(p.data)
   desc[idx].len = p.length
   r.write = inc(r.write)
end

function fill (r, p)
   local desc = ffi.cast("uint64_t *", r.desc)
   local idx = mask(r.write)
   desc[idx] = to_umem(p)
   r.write = inc(r.write)
end

function push (r)
   -- NB: no need for memory barrier on x86 because of TSO.
   r.producer[0] = r.write
end

function empty (r)
   if r.read == r.write then
      if r.read == r.producer[0] then
         return true
      end
      r.write = r.producer[0]
   end
end

local packet_overhead = 2 -- leading struct packet length field (uint16_t)
function receive (r)
   local desc = ffi.cast(xdp_desc_ptr_t, r.desc)
   local idx = mask(r.read)
   local p = ffi.cast("struct packet *",
                      -- packet struct begins at payload - packet_overhead
                      from_umem(desc[idx].addr) - packet_overhead)
   p.length = desc[idx].len
   r.read = inc(r.read)
   return p
end

function reclaim (r)
   -- NB: reclaim does not (re)set the payload length field.
   -- Reclaimed packets do *not* have known payload lengths!
   local desc = ffi.cast("uint64_t *", r.desc)
   local idx = mask(r.read)
   local p = ffi.cast("struct packet *", from_umem(desc[idx]))
   r.read = inc(r.read)
   return p
end

function pull (r)
   -- NB: no need for memory barrier on x86 (see push.)
   r.consumer[0] = r.read
end

function needs_wakeup (r)
   -- NB: Unavailable when kernel does not support ring flags.
   -- See: XDP.kernel_has_ring_flags, XDP:create_xsk(), XDP:kick()
   return band(r.flags[0], bits{XDP_RING_NEED_WAKEUP=1})
end

-- Rewind routines for transmit/fill. These are used by XDP:stop() to reclaim
-- packet buffers left in-fight after shutdown.

function rewind_transmit (r)
   r.write = tobit(r.write - 1)
   local desc = ffi.cast(xdp_desc_ptr_t, r.desc)
   local idx = mask(r.write)
   return ffi.cast("struct packet *",
                   -- packet struct begins at payload - packet_overhead
                   from_umem(desc[idx].addr) - packet_overhead)
end

function rewind_fill (r)
   r.write = tobit(r.write - 1)
   local desc = ffi.cast("uint64_t *", r.desc)
   local idx = mask(r.write)
   return ffi.cast("struct packet *", from_umem(desc[idx]))
end


-- ---- XDP App ---------------------------------------------------------

XDP = {
   config = {
      ifname = {required=true}, -- interface name
      filter = {},              -- interface pcap-filter(7) (optional)
      queue = {default=0}       -- interface queue (zero based)
   },
   -- Class variables:
   kernel_has_ring_flags = true -- feature detection status for descriptor ring flags
}

-- The `driver' variable is used as a reference to the driver class in
-- order to interchangeably use NIC drivers.
driver = XDP

-- Class methods

function XDP:new (conf)
   assert(snabb_xdp_enabled, "Snabb XDP mode must be enabled.")
   -- Ensure interface is initialized for XDP usage.
   local lockfd, mapfd = self:open_interface(conf.ifname, conf.filter)
   -- Create XDP socket (xsk) for queue.
   local xsk = self:create_xsk(conf.ifname, lockfd, conf.queue)
   -- Attach the socket to queue in the BPF map.
   self:set_queue_socket(mapfd, conf.queue, xsk)
   mapfd:close() -- not longer needed
   -- Finish initialization.
   return setmetatable(xsk, {__index=XDP})
end

function XDP:open_interface (ifname, filter)
   -- Open an interface-dependent file we know should exist to use as a
   -- Snabb-wide lock. The contents of the file are really irrelevant here.
   -- However, we depend on the file not being locked by other applications in
   -- general. :-) 
   local lockfd = S.open("/sys/class/net/"..ifname.."/operstate", "rdonly")
   local mapfd, progfd
   local xskmap_path = "/sys/fs/bpf/snabb/"..ifname.."/xskmap"
   local prog_path = "/sys/fs/bpf/snabb/"..ifname.."/xdp"
   -- If the open above failed we assume that no device by ifname exists.
   assert(lockfd, "Could not open interface: "..ifname.." (does it exist?)")
   if lockfd:flock("ex, nb") then
      -- If we get an exclusive lock we know that no other Snabb processes are
      -- using the interface so its safe to setup the interface and replace any
      -- existsing BPF XDP program/maps attached to it.
      S.mkdir("/sys/fs/bpf/snabb", "rwxu, rgrp, xgrp, roth, xoth")
      S.util.rm("/sys/fs/bpf/snabb/"..ifname)
      S.mkdir("/sys/fs/bpf/snabb/"..ifname, "rwxu, rgrp, xgrp, roth, xoth")
      -- Create xskmap and XDP program to run on the NIC.
      mapfd = self:create_xskmap()
      progfd = self:xdp_prog(mapfd, filter)
      self:set_link_xdp(ifname, progfd)
      -- Pin xskmap so it can be accessed by other Snabb processes to attach to
      -- the interface. Also pin the XDP program, just 'cause.
      assert(S.bpf_obj_pin(xskmap_path, mapfd))
      assert(S.bpf_obj_pin(prog_path, progfd))
      progfd:close() -- no longer needed
      lockfd:flock("sh") -- share lock
   else
      lockfd:flock("sh")
      -- Wait for the lock to be shared: once it is no longer held exclusively
      -- we know that the interface is setup and ready to use.
      -- Get the currently pinned xskmap to insert our XDP socket into.
      mapfd = assert(S.bpf_obj_get(xskmap_path))
   end
   -- lockfd: holds a shared lock for as long as we do not close it, signaling
   --         other Snabb processes that the interface is in use.
   -- mapfd: the xskmap for the interface used to
   --        attach XDP sockets to queues.
   return lockfd, mapfd
end

function XDP:create_xskmap ()
   local klen, vlen = ffi.sizeof("int"), ffi.sizeof("int")
   local nentries = 128
   local map, err
   for _ = 1,7 do
      -- Try to create BPF map.
      map, err = S.bpf_map_create('xskmap', klen, vlen, nentries)
      -- Return map on success.
      if map then return map end
      -- Failed to create map, increase MEMLOCK limit and retry.
      -- See https://github.com/xdp-project/xdp-tutorial/issues/63
      local lim = assert(S.getrlimit('memlock'))
      assert(S.setrlimit('memlock', {cur=lim.cur*2, max=lim.max*2}))
   end
   -- Exceeded retries, bail.
   error("Failed to create BPF map: "..tostring(err))
end

function XDP:xdp_prog (xskmap, filter)
   -- Assemble and load XDP BPF program.
   -- If we have a filter argument, compile a filter that passes non-matching
   -- packets on to the kernel networking stack (XDP_PASS). Append to it our
   -- regular XSK forwarding code (XDP:xdp_forward) so packets that pass
   -- the filter are forwarded to attached XDP sockets.
   local flt = (filter and pf.compile(filter)) or {}
   for _, ins in ipairs(self:xdp_forward(xskmap)) do
      -- Append forwarding logic to filter.
      table.insert(flt, ins)
   end
   local asm = bpf.asm(flt)
   local prog, err, log = S.bpf_prog_load(
      'xdp', asm, ffi.sizeof(asm) / ffi.sizeof(bpf.ins), "Apache 2.0"
   )
   if prog then
      return prog
   else
      error(tostring(err).."\n"..log)
   end
end

function XDP:xdp_forward (xskmap)
   local c, f, m, a, s, j, fn =
      bpf.c, bpf.f, bpf.m, bpf.a, bpf.s, bpf.j, bpf.fn
   -- The program below looks up the incoming packet's queue index in xskmap to
   -- find the corresponding XDP socket (xsk) to deliver the packet to.
   return {
      -- r3 = XDP_ABORTED
      { op=bor(c.ALU, a.MOV, s.K), dst=3, imm=0 },
      -- r2 = ((struct xdp_md *)ctx)->rx_queue_index
      { op=bor(c.LDX, f.W, m.MEM), dst=2, src=1, off=16 },
      -- r1 = xskmap
      { op=bor(c.LD, f.DW, m.IMM), dst=1, src=s.MAP_FD, imm=xskmap:getfd() },
      { imm=0 }, -- nb: upper 32 bits of 64-bit (DW) immediate
      -- r0 = redirect_map(r1, r2, r3)
      { op=bor(c.JMP, j.CALL), imm=fn.redirect_map },
      -- EXIT:
      { op=bor(c.JMP, j.EXIT) }
   }
end

function XDP:set_link_xdp (ifname, prog)
   -- Open a NETLINK socket, and transmit command that attaches XDP program
   -- prog to link by ifname.
   local netlink = assert(S.socket('netlink', 'raw', 'route'))
   local SOL_NETLINK = 270
   local NETLINK_EXT_ACK = 11
   local ext_ack_on = ffi.new("int[1]", 1)
   assert(S.setsockopt(netlink, SOL_NETLINK, NETLINK_EXT_ACK,
                       ext_ack_on, ffi.sizeof(ext_ack_on)))
   local IFLA_XDP = 43
   local IFLA_XDP_FD = 1
   local IFLA_XDP_FLAGS = 3
   local request = ffi.new(
      netlink_set_link_xdp_request_t,
      { nh        = { nlmsg_flags = bor(S.c.NLM_F.REQUEST, S.c.NLM_F.ACK),
                      nlmsg_type = S.c.RTM.SETLINK },
        ifinfo    = { ifi_family = S.c.AF.UNSPEC,
                      ifi_index = S.util.if_nametoindex(ifname) },
        xdp       = { nla_type = bor(bits{ NLA_F_NESTED=15 }, IFLA_XDP) },
        xdp_fd    = { nla_type = IFLA_XDP_FD,
                      fd = prog:getfd() } }
   )
   request.nh.nlmsg_len = ffi.sizeof(request)
   request.xdp.nla_len = ffi.sizeof(request.xdp) + ffi.sizeof(request.xdp_fd)
   request.xdp_fd.nla_len = ffi.sizeof(request.xdp_fd)
   assert(netlink:send(request, ffi.sizeof(request)))
   local response = assert(S.nl.read(netlink, nil, nil, true))
   if response.error then
      error("NETLINK responded with error: "..tostring(response.error))
   end
   netlink:close()
end

function XDP:create_xsk (ifname, lockfd, queue)
   local xsk = { sock = assert(S.socket('xdp', 'raw')), lockfd = lockfd }
   -- Register UMEM.
   local umem_reg = ffi.new(
      xdp_umem_reg_t,
      { addr = umem,
        len = umem_size,
        -- The chunk size is equal to the page size (4096 bytes, see
        -- "UMEM allocation"), and XDP packet descriptors point to individual
        -- chunks (see "XDP rings"). Hence, the MTU of AF_XDP sockets is
        -- limited to the page size, and the effective MTU of the XDP app is
        -- further limited by the way core.packet implements packet shifting
        -- operations (see headroom below). The effective MTU is calculated as
        --    4096 - packet.packet_alignment (512) - packet_overhead (2) = 3582
        chunk_size = chunk_size,
        -- By configuring the headroom according to core.packet we make sure
        -- that XDP leaves enough headroom for the preceeding length field of
        -- Snabb's struct packet as well as headroom for packet shifting
        -- operations.
        headroom = packet.default_headroom + packet_overhead,
        -- flags = bits{ XDP_UMEM_UNALIGNED_CHUNK_FLAG=1 }
      }
   )
   assert(xsk.sock:setsockopt('xdp', 'xdp_umem_reg', umem_reg, ffi.sizeof(umem_reg)))
   -- Configure XDP rings and map them into this process’ memory.
   local ndesc = ffi.new("int[1]", xdp_ring_ndesc)
   assert(xsk.sock:setsockopt('xdp', 'xdp_rx_ring', ndesc, ffi.sizeof(ndesc)))
   assert(xsk.sock:setsockopt('xdp', 'xdp_tx_ring', ndesc, ffi.sizeof(ndesc)))
   assert(xsk.sock:setsockopt('xdp', 'xdp_umem_fill_ring', ndesc, ffi.sizeof(ndesc)))
   assert(xsk.sock:setsockopt('xdp', 'xdp_umem_completion_ring', ndesc, ffi.sizeof(ndesc)))
   local layouts = ffi.new(xdp_mmap_offsets_t)
   if not pcall(S.getsockopt, xsk.sock, 'xdp', 'xdp_mmap_offsets', layouts, ffi.sizeof(layouts)) then
      -- Kernel appears not to support XDP ring flags field. Disable feature,
      -- and retry with xdp_mmap_offsets_noflags_t.
      self.kernel_has_ring_flags = false
      layouts = ffi.new(xdp_mmap_offsets_noflags_t)
      assert(xsk.sock:getsockopt('xdp', 'xdp_mmap_offsets', layouts, ffi.sizeof(layouts)))
   end
   xsk.rx = self:xdp_map_ring(xsk.sock, layouts.rx, xdp_desc_t, 0x000000000ULL) -- XDP_PGOFF_RX_RING
   xsk.tx = self:xdp_map_ring(xsk.sock, layouts.tx, xdp_desc_t, 0x080000000ULL) -- XDP_PGOFF_TX_RING
   -- NB: fill and completion rings do not carry full descriptors, only
   -- relative UMEM offsets (addr).
   xsk.fr = self:xdp_map_ring(xsk.sock, layouts.fr, "uint64_t", 0x100000000ULL) -- XDP_UMEM_PGOFF_FILL_RING
   xsk.cr = self:xdp_map_ring(xsk.sock, layouts.cr, "uint64_t", 0x180000000ULL) -- XDP_UMEM_PGOFF_COMPLETION_RING
   -- Counters to track packets in-flight through kernel.
   --    - rxq is incremented when a packet buffer is enqueued onto the
   --      fill ring and decremented when a packet buffer is dequeued from the
   --      tx ring. I.e., it tracks the number of unused buffers currently left
   --      on the fill ring.
   --    - txq is incremented when a packet buffer is enqueued onto the tx ring
   --      and decremented then a packet buffer is dequeued from the
   --      completion ring. I.e, it tracks number of unused buffers currently
   --      left on the tx ring.
   -- The rxq and txq tallies are used by XDP:stop() to perform a clean
   -- socket shutdown without leaking packet buffers.
   xsk.rxq = 0
   xsk.txq = 0
   -- Bind socket to interface
   local sa = ffi.new(
      sockaddr_xdp_t,
      { family = S.c.AF.XDP,
        ifindex = S.util.if_nametoindex(ifname),
        queue_id = queue,
        -- flags = bits{ XDP_ZEROCOPY=2 }
      }
   )
   local ok, err = xsk.sock:bind(sa, ffi.sizeof(sa))
   if not ok then
      error(("Unable to bind AF_XDP socket to %s queue %d (%s)")
            :format(ifname, queue, err))
   end
   return xsk
end

-- Map an XDP socket ring into this process’ memory.
function XDP:xdp_map_ring (socket, layout, desc_t, offset)
   local prot = "read, write"
   local flags = "shared, populate"
   local r = ffi.new(xdp_ring_t)
   r.maplen = layout.desc + xdp_ring_ndesc * ffi.sizeof(desc_t)
   r.map = assert(S.mmap(nil, r.maplen, prot, flags, socket, offset))
   r.producer = ffi.cast("uint32_t *", r.map + layout.producer)
   r.consumer = ffi.cast("uint32_t *", r.map + layout.consumer)
   if self.kernel_has_ring_flags then
      r.flags = ffi.cast("uint32_t *", r.map + layout.flags)
   end
   r.desc = r.map + layout.desc
   return r
end

function XDP:set_queue_socket(xskmap, queue, xsk)
   assert(S.bpf_map_op('map_update_elem', xskmap,
                       ffi.new("int[1]", queue),
                       ffi.new("int[1]", xsk.sock:getfd())))
end

-- Instance methods

function XDP:stop ()
   -- XXX - previous shutdown sequence was broken (see git history for details.)
   error("Can not stop XDP driver (operation not supported)")
end

function XDP:pull ()
   local output = self.output.output
   local rx = self.rx
   self:refill()
   if not output then return end
   for _ = 1, engine.pull_npackets do
      if empty(rx) then break end
      link.transmit(output, receive(rx))
      self.rxq = self.rxq - 1
   end
   pull(rx)
end

function XDP:push ()
   local input = self.input.input
   local tx = self.tx
   if not input then return end
   while not link.empty(input) and not full(tx) do
      local p = link.receive(input)
      transmit(tx, p)
      self.txq = self.txq + 1
      -- Stimulate breathing: after the kernel is done with the packet buffer
      -- it will either be fed back from the completion ring onto the free
      -- ring, or put back onto the freelist via packet.free_internal; hence,
      -- account statistics for freed packet here in order to signal to the
      -- engine that throughput is happening.
      packet.account_free(p)
   end
   push(tx)
   if self.kernel_has_ring_flags then
      if needs_wakeup(tx) then self:kick() end
   else
      if not empty(tx) then self:kick() end
   end
end

function XDP:refill ()
   local input, output = self.input.input, self.output.output
   local fr, cr = self.fr, self.cr
   -- If the queue operates in duplex mode (i.e., has both input and output
   -- links attached) we feed packet buffers from the completion ring back onto
   -- the fill ring.
   if input and output then
      while not (empty(cr) or full(fr)) do
         fill(fr, reclaim(cr))
         self.txq = self.txq - 1
         self.rxq = self.rxq + 1
      end
   end
   -- If the queue has its output attached we make sure that the kernel does
   -- not run out of packet buffers to fill the rx ring with by keeping the
   -- fill ring topped up with fresh packets.
   -- (If no input is attached, the completion ring is not used, and
   -- all packet buffers for rx will be allocated here.)
   if output then
      while not full(fr) do
         fill(fr, packet.allocate())
         self.rxq = self.rxq + 1
      end
   end
   -- If the queue has its input attached we release any packet buffers
   -- remaining in the completion ring back to the packet freelist.
   -- (If not output is attached, the fill ring is not used, and
   -- all packet buffers used for tx will be reclaimed here.)
   if input then
      while not empty(cr) do
         -- NB: mandatory free_internal since we do not know the payload length
         -- of reclaimed packets.
         packet.free_internal(reclaim(cr))
         self.txq = self.txq - 1
      end
   end
   push(fr)
   pull(cr)
end

function XDP:kick ()
   -- Wake up Linux kernel to process tx ring packets.
   self.sock:sendto(nil, 0, 'dontwait', nil, 0)
end


-- ---- Tests -----------------------------------------------------------

-- Useful setup commands:
--  $ echo 0000:01:00.0 > /sys/bus/pci/drivers/ixgbe/bind
--  $ ip link set ens1f0 addr 02:00:00:00:00:00
--  $ ethtool --set-channels ens1f0 combined 1

function selftest_init ()
   local xdpdeva = lib.getenv("SNABB_XDP0")
   local xdpmaca = lib.getenv("SNABB_XDP_MAC0")
   local xdpdevb = lib.getenv("SNABB_XDP1")
   local xdpmacb = lib.getenv("SNABB_XDP_MAC1")
   local nqueues = tonumber(lib.getenv("SNABB_XDP_NQUEUES")) or 1
   if not (xdpdeva and xdpmaca and xdpdevb and xdpmacb) then
      print("SNABB_XDP0 and SNABB_XDP1 must be set. Skipping selftest.")
      os.exit(engine.test_skipped_code)
   end
   snabb_enable_xdp()
   engine.report_load()
   return xdpdeva, xdpmaca, xdpdevb, xdpmacb, nqueues
end


function selftest ()
   print("selftest: apps.xdp.xdp")
   local xdpdeva, xdpmaca, xdpdevb, xdpmacb, nqueues = selftest_init()
   if nqueues > 1 then
      os.exit(engine.test_skipped_code)
   end
   print("test: rxtx_match")
   selftest_rxtx_match(xdpdeva, xdpmaca, xdpdevb, xdpmacb)
   -- NB: see also test_*.lua
   print("selftest ok")
end

local function random_v4_packets (conf)
   local ethernet = require("lib.protocol.ethernet")
   local ipv4 = require("lib.protocol.ipv4")
   local eth = ethernet:new{src = ethernet:pton(conf.src),
                            dst = ethernet:pton(conf.dst),
                            type = 0x0800}
   local packets = {}
   for _, size in ipairs(conf.sizes) do
      for _=1,100 do
         local ip = ipv4:new{src=lib.random_bytes(4),
                             dst=lib.random_bytes(4)}
         if conf.protocol then ip:protocol(conf.protocol) end
         ip:total_length(size - eth:sizeof())
         local payload_length = ip:total_length() - ip:sizeof()
         local p = packet.allocate()
         packet.append(p, eth:header(), eth:sizeof())
         packet.append(p, ip:header(), ip:sizeof())
         packet.append(p, lib.random_bytes(payload_length), payload_length)
         table.insert(packets, p)
      end
   end
   return packets
end

function selftest_rxtx (xdpdeva, xdpmaca, xdpdevb, xdpmacb, nqueues)
   local c = config.new()
   local basic = require("apps.basic.basic_apps")
   local synth = require("apps.test.synth")
   config.app(c, "source", synth.Synth, {
                 packets = random_v4_packets{
                    sizes = {60},
                    src = xdpmaca,
                    dst = xdpmacb
   }})
   config.app(c, "sink", basic.Sink)
   for queue = 0, nqueues-1 do
      local queue_a = xdpdeva.."_q"..queue
      local queue_b = xdpdevb.."_q"..queue
      config.app(c, queue_a, XDP, {
                    ifname = xdpdeva,
                    queue = queue
      })
      config.app(c, queue_b, XDP, {
                    ifname = xdpdevb,
                    queue = queue
      })
      config.link(c, "source.output"..queue.." -> "..queue_a..".input")
      config.link(c, queue_b..".output -> sink.input"..queue)
   end
   engine.configure(c)
   print("kernel_has_ring_flags", XDP.kernel_has_ring_flags)
   engine.main{ duration=1 }
   engine.report_links()
   local txtotal, rxtotal = 0, 0
   for queue = 0, nqueues-1 do
      local tx = link.stats(engine.app_table.source.output["output"..queue])
      local rx = link.stats(engine.app_table.sink.input["input"..queue])
      assert(tx.rxpackets > 0, "No packets sent on queue: "..queue)
      assert(rx.rxpackets > 0, "No packets received on queue: "..queue)
      txtotal = txtotal + tx.rxpackets
      rxtotal = rxtotal + rx.rxpackets
   end
   assert(math.abs(txtotal - rxtotal) <= txtotal*.10, -- 10% tolerance
          "Too little packets received")
end

function selftest_duplex (xdpdeva, xdpmaca, xdpdevb, xdpmacb, nqueues)
   local c = config.new()
   local basic = require("apps.basic.basic_apps")
   local synth = require("apps.test.synth")
   config.app(c, "source_a", synth.Synth, {
                 packets = random_v4_packets{
                    sizes = {60},
                    src = xdpmaca,
                    dst = xdpmacb
   }})
   config.app(c, "source_b", synth.Synth, {
                 packets = random_v4_packets{
                    sizes = {60},
                    src = xdpmacb,
                    dst = xdpmaca
   }})
   config.app(c, "sink", basic.Sink)
   for queue = 0, nqueues-1 do
      local queue_a = xdpdeva.."_q"..queue
      local queue_b = xdpdevb.."_q"..queue
      config.app(c, queue_a, XDP, {
                    ifname = xdpdeva,
                    queue = queue
      })
     config.app(c, queue_b, XDP, {
                   ifname = xdpdevb,
                   queue = queue
     })
      config.link(c, "source_a.output"..queue.." -> "..queue_a..".input")
      config.link(c, "source_b.output"..queue.." -> "..queue_b..".input")
      config.link(c, queue_a..".output -> sink.input_a"..queue)
      config.link(c, queue_b..".output -> sink.input_b"..queue)
   end
   engine.configure(c)
   print("kernel_has_ring_flags", XDP.kernel_has_ring_flags)
   engine.main{ duration=1 }
   engine.report_links()
   for label, stream in ipairs{
      ['a->b'] = {'a','b'},
      ['b->a'] = {'b','a'}
   } do
      local txtotal, rxtotal = 0, 0
      for queue = 0, nqueues-1 do
         local tx = link.stats(engine.app_table["source_"..stream[0]].output["output_"..queue])
         local rx = link.stats(engine.app_table.sink.input["input_"..stream[1]..queue])
         assert(tx.rxpackets > 0, "["..label"..] No packets sent on queue: "..queue)
         assert(rx.rxpackets > 0, "["..label"..] No packets received on queue: "..queue)
         txtotal = txtotal + tx.rxpackets
         rxtotal = rxtotal + rx.rxpackets
      end
      assert(math.abs(txtotal - rxtotal) <= txtotal*.10, -- 10% tolerance
             "["..label"..] Too little packets received")
   end
end

function selftest_rxtx_match (xdpdeva, xdpmaca, xdpdevb, xdpmacb)
   local c = config.new()
   local synth = require("apps.test.synth")
   local npackets = require("apps.test.npackets")
   local match = require("apps.test.match")
   config.app(c, "source", synth.Synth, {
                 sizes = {60,64,67,128,133,192,256,384,512,777,1024,1500,1501},
                 src = xdpmaca,
                 dst = xdpmacb,
                 random_payload = true
   })
   config.app(c, "npackets", npackets.Npackets, {npackets=1000})
   config.app(c, "match", match.Match)
   config.app(c, xdpdeva.."_q0", XDP, {ifname=xdpdeva})
   config.app(c, xdpdevb.."_q0", XDP, {ifname=xdpdevb})
   config.link(c, "source.output -> "..xdpdeva.."_q0.input")
   config.link(c, xdpdevb.."_q0.output -> match.rx")
   config.link(c, "source.copy -> npackets.input")
   config.link(c, "npackets.output -> match.comparator")
   engine.configure(c)
   engine.main{ duration=.1 }
   engine.report_links()
   engine.report_apps()
   assert(#engine.app_table.match:errors() == 0, "Match errors.")
end

function selftest_rxtx_match_filter (xdpdeva, xdpmaca, xdpdevb, xdpmacb)
   local c = config.new()
   local synth = require("apps.test.synth")
   local npackets = require("apps.test.npackets")
   local match = require("apps.test.match")
   config.app(c, "source", synth.Synth, {
                 packets = random_v4_packets{
                    sizes = {60,64,67,128,133,192,256,384,512,777,1024,1500,1501},
                    src = xdpmaca,
                    dst = xdpmacb,
                    protocol = 42
   }})
   config.app(c, "npackets", npackets.Npackets, {npackets=1000})
   config.app(c, "match", match.Match)
   config.app(c, xdpdeva, XDP, {ifname=xdpdeva})
   config.app(c, xdpdevb, XDP, {ifname=xdpdevb, filter="ip proto 42"})
   config.link(c, "source.output -> "..xdpdeva..".input")
   config.link(c, xdpdevb..".output -> match.rx")
   config.link(c, "source.copy -> npackets.input")
   config.link(c, "npackets.output -> match.comparator")
   -- Test redirect
   engine.configure(c)
   engine.main{ duration=.1 }
   engine.report_links()
   engine.report_apps()
   assert(#engine.app_table.match:errors() == 0, "Match errors.")
end

function selftest_rxtx_match_filter_pass (xdpdeva, xdpmaca, xdpdevb, xdpmacb)
   local c = config.new()
   local synth = require("apps.test.synth")
   local npackets = require("apps.test.npackets")
   local match = require("apps.test.match")
   config.app(c, "source", synth.Synth, {
                 packets = random_v4_packets{
                    sizes = {60,64,67,128,133,192,256,384,512,777,1024,1500,1501},
                    src = xdpmaca,
                    dst = xdpmacb,
                    protocol = 42
   }})
   config.app(c, "npackets", npackets.Npackets, {npackets=1000})
   config.app(c, "match", match.Match)
   config.app(c, xdpdeva, XDP, {ifname=xdpdeva})
   config.app(c, xdpdevb, XDP, {ifname=xdpdevb, filter="ip proto 42"})
   config.link(c, "source.output -> "..xdpdeva..".input")
   config.link(c, xdpdevb..".output -> match.rx")
   config.link(c, "source.copy -> npackets.input")
   config.link(c, "npackets.output -> match.comparator")
   -- Test pass
   config.app(c, xdpdevb, XDP, {ifname=xdpdevb, filter="ip6 proto 77"})
   engine.configure(c)
   engine.main{ duration=.1 }
   engine.report_links()
   assert(#engine.app_table.match:errors() == 1000, "Matched packets.")
   assert(link.stats(engine.app_table[xdpdevb].output.output).rxpackets == 0,
          "Too many packets received on "..xdpdevb)
end

function selftest_share_interface_worker (xdpdev, queue)
   snabb_enable_xdp()
   local c = config.new()
   local basic = require("apps.basic.basic_apps")
   local recv = xdpdev.."_q"..queue
   config.app(c, recv, XDP, {
                 ifname = xdpdev,
                 queue = queue
   })
   config.app(c, "sink", basic.Sink)
   config.link(c, recv..".output -> sink.input")
   engine.configure(c)
   engine.main{ duration=.1, no_report = true }
   print("[worker links]")
   engine.report_links()
   assert(link.stats(engine.app_table.sink.input.input).rxpackets > 0,
          "No packets received on "..recv.." in worker.")
end

function selftest_share_interface (xdpdeva, xdpmaca, xdpdevb, xdpmacb, nqueues)
   local c = config.new()
   local worker = require("core.worker")
   local basic = require("apps.basic.basic_apps")
   local synth = require("apps.test.synth")
   config.app(c, "source", synth.Synth, {
                 packets = random_v4_packets{
                    sizes = {60},
                    src = xdpmaca,
                    dst = xdpmacb
   }})
   config.app(c, "sink", basic.Sink)
   for queue = 0, nqueues-2 do
      local queue_a = xdpdeva.."_q"..queue
      local queue_b = xdpdevb.."_q"..queue
      config.app(c, queue_a, XDP, {
                    ifname = xdpdeva,
                    queue = queue
      })
     config.app(c, queue_b, XDP, {
                   ifname = xdpdevb,
                   queue = queue
     })
      config.link(c, "source.output"..queue.." -> "..queue_a..".input")
      config.link(c, queue_b..".output -> sink.input"..queue)
   end
   engine.configure(c)
   worker.start('worker', ("require('apps.xdp.xdp').selftest_share_interface_worker('%s', %d)")
                   :format(xdpdevb, nqueues-1))
   engine.main{ done=function () return not worker.status().worker.alive end,
                no_report = true }
   local worker_status = worker.status().worker.status
   print("[parent links]")
   engine.report_links()
   if worker_status ~= 0 then
      os.exit(worker_status)
   end
end
