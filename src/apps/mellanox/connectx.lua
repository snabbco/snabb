-- Device driver for the Mellanox ConnectX-4+ Ethernet controller family.
-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- This is a device driver for Mellanox ConnectX family ethernet
-- cards. This driver is completely stand-alone and does not depend on
-- any other software such as Mellanox OFED library or the Linux mlx5
-- driver.
--
-- Thanks are due to Mellanox and Deutsche Telekom for making it
-- possible to develop this driver based on publicly available
-- information. Mellanox supported this work by releasing an edition
-- of their Programming Reference Manual (PRM) that is not subject to
-- confidentiality restrictions. This is now a valuable resource to
-- independent open source developers everywhere (spread the word!)
--
-- Special thanks to Normen Kowalewski and Rainer Schatzmayer.

-- General notes about this implementation:
--
--   The driver is based primarily on the PRM:
--   http://www.mellanox.com/related-docs/user_manuals/Ethernet_Adapters_Programming_Manual.pdf
--
--   The Linux mlx5_core driver is also used for reference. This
--   driver implements the same hexdump format as mlx5_core so it is
--   possible to directly compare/diff the binary encoded commands
--   that the drivers send.
--
--   Physical addresses are always used for DMA (rlkey).

module(...,package.seeall)

local ffi      = require "ffi"
local C        = ffi.C
local lib      = require("core.lib")
local sync     = require("core.sync")
local pci      = require("lib.hardware.pci")
local register = require("lib.hardware.register")
local index_set = require("lib.index_set")
local macaddress = require("lib.macaddress")
local mib = require("lib.ipc.shmem.mib")
local timer = require("core.timer")
local shm = require("core.shm")
local counter = require("core.counter")
local bits, bitset = lib.bits, lib.bitset
local floor = math.floor
local cast = ffi.cast
local ethernet = require("lib.protocol.ethernet")

local band, bor, shl, shr, bswap, bnot =
   bit.band, bit.bor, bit.lshift, bit.rshift, bit.bswap, bit.bnot
local cast, typeof = ffi.cast, ffi.typeof

local debug_info    = false     -- Print into messages
local debug_trace   = false     -- Print trace messages
local debug_hexdump = false     -- Print hexdumps (in Linux mlx5 format)

-- Maximum size of a receive queue table.
-- XXX This is hard-coded in the Linux mlx5 driver too. Could
-- alternatively detect from query_hca_cap.
local rqt_max_size = 128

---------------------------------------------------------------
-- CXQ (ConnectX Queue pair) control object:
-- 
-- A "CXQ" is an object that we define to represent a transmit/receive pair.
-- 
-- CXQs are created and deleted by a "Control" app and, in between,
-- they are used by "IO" apps to send and receive packets.
-- 
-- The lifecycle of a CXQ is managed using a state machine. This is
-- necessary because we allow Control and IO apps to start in any
-- order, for Control and IO apps to start/stop/restart independently,
-- for multiple IO apps to attempt to attach to the same CXQ, and even
-- for apps to stop in one Snabb process and be started in another
-- one.
-- 
-- (This design may turn out to be overkill if we discover in the
-- future that we do not need this much flexibility. Time will tell.)
---------------------------------------------------------------

-- CXQs can be in one of five states:
--   INIT: CXQ is being initialized by the control app
--   FREE: CXQ is ready and available for use by an IO app.
--   IDLE: CXQ is owned by an app, but not actively processing right now.
--   BUSY: CXQ is owned by an app and is currently processing (e.g. push/pull).
--   DEAD: CXQ has been deallocated; IO app must try to open a new one.
-- 
-- Once a CXQ is closed it stays in the DEAD state forever. However, a
-- replacement CXQ with the same name can be created and existing IO
-- apps can reattach to that instead. This will rerun the state machine.
--
-- Here are the valid state transitions & when they occur:
--
-- App  Change      Why
-- ---- ----------- --------------------------------------------------------
-- CTRL none->INIT: Control app starts initialization.
-- CTRL INIT->FREE: Control app completes initialization.
-- IO   FREE->IDLE: IO app starts and becomes owner of the CXQ.
-- IO   IDLE->FREE: IO app stops and releases the CXQ for future use.
-- IO   IDLE->BUSY: IO app starts running a pull/push method.
-- IO   BUSY->IDLE: IO app stops running a pull/push method.
-- CTRL IDLE->DEAD: Control app closes the CXQ. (Replacement can be created.)
-- CTRL FREE->DEAD: Control app closes the CXQ. (Replacement can be created.)
-- 
-- These state transitions are *PROHIBITED* for important reasons:
--
-- App    Change      Why *PROHIBITED*
-- ------ ----------- --------------------------------------------------------
-- CTRL   BUSY->DEAD  Cannot close a CXQ while it is busy (must wait.)
-- IO     DEAD->BUSY  Cannot use a CXQ that is closed (must check.)
-- *      DEAD->*     Cannot transition from DEAD (must create new CXQ.)
--
-- Further notes:
-- 
--   Packet buffers for pending DMA (transmit or receive) are freed by
--   the Control app (which can disable DMA first) rather than by the IO
--   app (which shuts down with DMA still active.)

-- A CXQ is represented by one struct allocated in shared memory.
-- 
-- The struct defines the fields in very specific terms so that it can
-- be used directly by the driver code (rather than copying back and
-- forth between the shared memory object and a separate native
-- format.)
local cxq_t = ffi.typeof([[
  struct {
    int state[1];    // current state / availability

    // configuration information:
    uint32_t sqn;      // send queue number
    uint32_t sqsize;   // send queue size
    uint32_t uar;      // user access region
    uint32_t rlkey;    // rlkey for value
    uint32_t rqn;      // receive queue number
    uint32_t rqsize;   // receive queue size

    // DMA structures:
    // doorbell contains send/receive ring cursor positions
    struct { uint32_t receive, send; } *doorbell;

    // receive work queue
    struct { uint32_t length, lkey, dma_hi, dma_lo; } *rwq;

    // send work queue and send/receive completion queues
    union { uint8_t u8[64]; uint32_t u32[0]; uint64_t u64[0];} *swq, *scq, *rcq;

    // The tx and rx lists must each be large enough for the maximum
    // queue size, which currently is 32768.  We should probably add
    // a check for that.

    // Transmit state
    struct packet *tx[64*1024]; // packets queued for transmit
    uint16_t next_tx_wqeid;     // work queue ID for next transmit descriptor
    uint64_t *bf_next, *bf_alt; // "blue flame" to ring doorbell (alternating)

    // Receive state
    struct packet *rx[64*1024]; // packets queued for receive
    uint16_t next_rx_wqeid;     // work queue ID for next receive descriptor
    uint32_t rx_cqcc;           // consumer counter of RX CQ
  }
]])

-- CXQ states:
local INIT = 0 -- Implicit initial state due to 0 value.
local BUSY = 1
local IDLE = 2
local FREE = 3
local DEAD = 4

-- Release CXQ after process termination.  Called from
-- core.main.shutdown
function shutdown(pid)
   for _, pciaddr in ipairs(shm.children("/"..pid.."/mellanox")) do
      for _, queue in ipairs(shm.children("/"..pid.."/mellanox/"..pciaddr)) do
         -- NB: this iterates the backlinks created by IO apps!
         -- Meaning, this cleans up CXQ attachments from dying IO apps.
         -- The actual CXQ objects are cleaned up in the process running
         -- the Control app (see ConnectX:stop()).
         -- The code below is just to make sure crashing IO apps do not block
         -- the Control app.
         local backlink = "/"..pid.."/mellanox/"..pciaddr.."/"..queue
         local shm_name = "/"..pid.."/group/pci/"..pciaddr.."/"..queue
         if shm.exists(shm_name) then
            local cxq = shm.open(shm_name, cxq_t)
            assert(sync.cas(cxq.state, IDLE, FREE) or
                      sync.cas(cxq.state, BUSY, FREE),
                   "ConnectX: failed to free "..shm_name..
                      " during shutdown")
         end
         shm.unlink(backlink)
      end
   end
end

---------------------------------------------------------------
-- ConnectX Snabb app.
--
-- Uses the driver routines to implement ConnectX-4 support in
-- the Snabb app network.
---------------------------------------------------------------

ConnectX = {}
ConnectX.__index = ConnectX

local mlx_types = {
   ["0x1013" ] = 4, -- ConnectX4
   ["0x1017" ] = 5, -- ConnectX5
   ["0x1019" ] = 5, -- ConnectX5
   ["0x101d" ] = 6, -- ConnectX6
}

ConnectX.config = {
   pciaddress   = { required = true },
   sendq_size   = { default  = 1024 },
   recvq_size   = { default  = 1024 },
   mtu          = { default  = 9500 },
   fc_rx_enable = { default  = false },
   fc_tx_enable = { default  = false },
   queues       = { required = true },
   macvlan      = { default  = false },
   sync_stats_interval = {default = 1}
}
local queue_config = {
   id   = { required = true },
   mac  = { default = nil },
   vlan = { default = nil },
   enable_counters = { default = true },
}

function ConnectX:new (conf)
   local self = setmetatable({}, self)
   local queues = {}
   for _, queue in ipairs(conf.queues) do
      table.insert(queues, lib.parse(queue, queue_config))
   end

   local pciaddress = pci.qualified(conf.pciaddress)
   local device_info = pci.device_info(pciaddress)
   self.mlx = assert(mlx_types[device_info.device],
                     "Unsupported device "..device_info.device)

   local sendq_size = conf.sendq_size
   local recvq_size = conf.recvq_size

   local mtu = conf.mtu

   -- Perform a hard reset of the device to bring it into a blank state.
   --
   -- Reset is performed at PCI level instead of via firmware command.
   -- This is intended to be robust to problems like bad firmware states.
   pci.unbind_device_from_linux(pciaddress)
   pci.reset_device(pciaddress)
   pci.set_bus_master(pciaddress, true)

   -- Setup the command channel
   --
   local fd = pci.open_pci_resource_locked(pciaddress, 0)
   local mmio = pci.map_pci_memory(fd)
   local init_seg = InitializationSegment:new(mmio)
   local hca_factory = HCA_factory(init_seg)
   local hca = hca_factory:new()

   -- Makes enable_hca() hang with ConnectX5
   if self.mlx == 4 then
      init_seg:reset()
   end
   if debug_trace then init_seg:dump() end
   while not init_seg:ready() do
      C.usleep(1000)
   end

   -- Boot the card
   --
   hca:enable_hca()
   hca:set_issi(1)
   hca:alloc_pages(hca:query_pages("boot"))
   local max_cap = hca:query_hca_general_cap('max')
   if debug_trace then self:dump_capabilities(hca) end

   -- Initialize the card
   --
   hca:alloc_pages(hca:query_pages("init"))
   hca:init_hca()
   hca:alloc_pages(hca:query_pages("regular"))

   if debug_trace then self:check_vport() end

   hca:set_port_mtu(mtu)
   hca:modify_nic_vport_context(mtu, true, true, true)

   hca:set_port_flow_control(conf.fc_rx_enable, conf.fc_tx_enable)

   -- Create basic objects that we need
   --
   local uar = hca:alloc_uar()
   local eq = hca:create_eq(uar)
   local pd = hca:alloc_protection_domain()
   local tdomain = hca:alloc_transport_domain()
   local rlkey = hca:query_rlkey()

   -- CXQ objects managed by this control app
   local cxq_shm = {}

   -- List of all receive queues for hashing traffic across
   local rqlist = {}
   local rqs = {}

   -- List of queue counter IDs and their corresponding queue IDs from
   -- the configuration (ConnectX5 and up)
   local q_counters = {}

   -- Enable MAC/VLAN switching?
   local usemac = false
   local usevlan = false

   -- Lists of receive queues by macvlan (used if usemac=true)
   local macvlan_rqlist = {}

   for _, queue in ipairs(queues) do
      -- Create a shared memory object for controlling the queue pair
      local shmpath = "group/pci/"..pciaddress.."/"..queue.id
      local cxq = shm.create(shmpath, cxq_t)
      cxq_shm[shmpath] = cxq

      local function check_qsize (type, size)
         assert(check_pow2(size),
                string.format("%s: %s queue size must be a power of 2: %d",
                              conf.pciaddress, type, size))
         assert(log2size(size) <= max_cap['log_max_wq_sz'],
                string.format("%s: %s queue size too big: requested %d, allowed %d",
                              conf.pciaddress, type, size,
                              math.pow(2, max_cap['log_max_wq_sz'])))
      end

      check_qsize("Send", sendq_size)
      check_qsize("Receive", recvq_size)

      cxq.rlkey = rlkey
      cxq.sqsize = sendq_size
      cxq.rqsize = recvq_size
      cxq.uar = uar
      local scqn, scqe = hca:create_cq(1, uar, eq.eqn, true)
      local rcqn, rcqe = hca:create_cq(recvq_size, uar, eq.eqn, false)
      cxq.scq = cast(typeof(cxq.scq), scqe)
      cxq.rcq = cast(typeof(cxq.rcq), rcqe)
      cxq.doorbell = cast(typeof(cxq.doorbell), memory.dma_alloc(16))

      local rq_stride = ffi.sizeof(ffi.typeof(cxq.rwq[0]))
      local sq_stride = ffi.sizeof(ffi.typeof(cxq.swq[0]))
      local workqueues = memory.dma_alloc(sq_stride * sendq_size +
                                             rq_stride *recvq_size, 4096)
      cxq.rwq = cast(ffi.typeof(cxq.rwq), workqueues)
      cxq.swq = cast(ffi.typeof(cxq.swq), workqueues + rq_stride * recvq_size)
      -- Create the queue objects
      local tis = hca:create_tis(0, tdomain)
      local counter_set_id
      if self.mlx > 4 and queue.enable_counters then
         counter_set_id = hca:alloc_q_counter()
         table.insert(q_counters, { counter_id = counter_set_id,
                                    queue_id   = queue.id })
      end
      -- XXX order check
      cxq.sqn = hca:create_sq(scqn, pd, sq_stride, sendq_size,
                              cxq.doorbell, cxq.swq, uar, tis)
      cxq.rqn = hca:create_rq(rcqn, pd, rq_stride, recvq_size,
                              cxq.doorbell, cxq.rwq,
                              counter_set_id)
      hca:modify_sq(cxq.sqn, 0, 1) -- RESET -> READY
      hca:modify_rq(cxq.rqn, 0, 1) -- RESET -> READY

      -- CXQ is now fully initialized & ready for attach.
      assert(sync.cas(cxq.state, INIT, FREE))

      usemac = usemac or (queue.mac ~= nil)
      usevlan = usevlan or (queue.vlan ~= nil)

      -- XXX collect for flow table construction
      rqs[queue.id] = cxq.rqn
      rqlist[#rqlist+1] = cxq.rqn
   end
   
   if usemac then
      -- Collect macvlan_rqlist for flow table construction
      for _, queue in ipairs(conf.queues) do
         assert(queue.mac, "Queue does not specifiy MAC: "..queue.id)
         if usevlan then
            assert(queue.vlan, "Queue does not specify a VLAN: "..queue.id)
         end
         local vlan = queue.vlan or false
         local mac = queue.mac
         if not macvlan_rqlist[vlan] then
            macvlan_rqlist[vlan] = {}
         end
         if not macvlan_rqlist[vlan][mac] then
            macvlan_rqlist[vlan][mac] = {}
         end
         table.insert(macvlan_rqlist[vlan][mac], rqs[queue.id])
      end
   elseif usevlan then
      error("NYI: promisc vlan")
   end

   local function setup_rss_rxtable (rqlist, tdomain, level)
      -- Set up RSS accross all queues. Hashing is only performed for
      -- IPv4/IPv6 with or without TCP/UDP. All non-IP packets are
      -- mapped to Queue #1.  Hashing is done by the TIR for a
      -- specific combination of header values, hence separate flows
      -- are needed to provide each TIR with the appropriate types of
      -- packets.
      local l3_protos = { 'v4', 'v6' }
      local l4_protos = { 'udp', 'tcp' }
      local rxtable = hca:create_flow_table(
         -- #rules = #l3*l4 rules + #l3 rules + 1 wildcard rule
         NIC_RX, level, #l3_protos * #l4_protos + #l3_protos + 1
      )
      local rqt = hca:create_rqt(rqlist)
      local index = 0
      -- Match TCP/UDP packets
      local flow_group_ip = hca:create_flow_group_ip(
         rxtable, NIC_RX, index, index + #l3_protos * #l4_protos - 1
      )
      for _, l3_proto in ipairs(l3_protos) do
         for _, l4_proto in ipairs(l4_protos) do
            local tir = hca:create_tir_indirect(rqt, tdomain,
                                                l3_proto, l4_proto)
            -- NOTE: flow table entries will only match if the packet
            -- contains the complete L4 header. Keep this in mind when
            -- processing truncated packets (e.g. from a port-mirror).
            -- If the header is incomplete, the packet will fall through
            -- to the wildcard match and end up in the first queue.
            hca:set_flow_table_entry_ip(rxtable, NIC_RX, flow_group_ip,
                                        index, TIR, tir, l3_proto, l4_proto)
            index = index + 1
         end
      end
      -- Fall-through for non-TCP/UDP IP packets
      local flow_group_ip_l3 = hca:create_flow_group_ip(
         rxtable, NIC_RX, index, index + #l3_protos - 1, "l3-only"
      )
      for _, l3_proto in ipairs(l3_protos) do
         local tir = hca:create_tir_indirect(rqt, tdomain, l3_proto, nil)
         hca:set_flow_table_entry_ip(rxtable, NIC_RX, flow_group_ip_l3,
                                     index, TIR, tir, l3_proto, nil)
         index = index + 1
      end
      -- Fall-through for non-IP packets
      local flow_group_wildcard =
         hca:create_flow_group_wildcard(rxtable, NIC_RX, index, index)
      local tir_q1 = hca:create_tir_direct(rqlist[1], tdomain)
      hca:set_flow_table_entry_wildcard(rxtable, NIC_RX,
                                        flow_group_wildcard, index, TIR, tir_q1)
      return rxtable
   end

   local function setup_macvlan_rxtable (macvlan_rqlist, usevlan, tdomain, level)
      -- Set up MAC+VLAN switching.
      -- 
      -- For Unicast switch [MAC+VLAN->RSS->TIR]. I.e., forward packets
      -- destined for a MAC+VLAN tuple to a RSS table containing all queues
      -- belonging to that tuple.
      -- (See notes on RSS in setup_rss_rxtable above.)
      -- 
      -- For Multicast switch [VLAN->TIR+]. I.e., forward multicast packets
      -- destined for a VLAN to the first queue of every MAC in that VLAN.
      -- 
      local macvlan_size, mcast_size = 0, 0
      for vlan in pairs(macvlan_rqlist) do
         mcast_size = mcast_size + 1
         for mac in pairs(macvlan_rqlist[vlan]) do
            macvlan_size = macvlan_size + 1
         end
      end
      local rxtable = hca:create_flow_table(
         NIC_RX, level, macvlan_size + mcast_size
      )
      local index = 0
      -- Unicast flow table entries
      local flow_group_macvlan = hca:create_flow_group_macvlan(
         rxtable, NIC_RX, index, index + macvlan_size - 1, usevlan
      )
      for vlan in pairs(macvlan_rqlist) do
         for mac, rqlist in pairs(macvlan_rqlist[vlan]) do
            local tid = setup_rss_rxtable(rqlist, tdomain, 1)
            hca:set_flow_table_entry_macvlan(rxtable, NIC_RX, flow_group_macvlan, index,
                                             FLOW_TABLE, tid, macaddress:new(mac), vlan)
            index = index + 1
         end
      end
      -- Multicast flow table entries
      local flow_group_mcast = hca:create_flow_group_macvlan(
         rxtable, NIC_RX, index, index + mcast_size - 1, usevlan, 'mcast'
      )
      local mac_mcast = macaddress:new("01:00:00:00:00:00")
      for vlan in pairs(macvlan_rqlist) do
         local mcast_tirs = {}
         for mac, rqlist in pairs(macvlan_rqlist[vlan]) do
            mcast_tirs[#mcast_tirs+1] = hca:create_tir_direct(rqlist[1], tdomain)
         end
         hca:set_flow_table_entry_macvlan(rxtable, NIC_RX, flow_group_mcast, index,
                                          TIR, mcast_tirs, mac_mcast, vlan, 'mcast')
         index = index + 1
      end
      return rxtable
   end

   if usemac then
      local rxtable = setup_macvlan_rxtable(macvlan_rqlist, usevlan, tdomain, 0)
      hca:set_flow_table_root(rxtable, NIC_RX)
   else
      local rxtable = setup_rss_rxtable(rqlist, tdomain, 0)
      hca:set_flow_table_root(rxtable, NIC_RX)
   end

   self.shm = {
      mtu    = {counter, mtu},
      txdrop = {counter}
   }

   local vport_context = hca:query_nic_vport_context()
   local frame = {
      dtime     = {counter, C.get_unix_time()},
      -- Keep a copy of the mtu here to have all
      -- data available in a single shm frame
      mtu       = {counter, mtu},
      speed     = {counter},
      status    = {counter, 2}, -- Link down
      type      = {counter, 0x1000}, -- ethernetCsmacd
      promisc   = {counter, vport_context.promisc_all},
      macaddr   = {counter, vport_context.permanent_address.bits},
      rxbytes   = {counter},
      rxpackets = {counter},
      rxmcast   = {counter},
      rxbcast   = {counter},
      rxdrop    = {counter},
      rxerrors  = {counter},
      txbytes   = {counter},
      txpackets = {counter},
      txmcast   = {counter},
      txbcast   = {counter},
      txdrop    = {counter},
      txerrors  = {counter},
   }
   -- Create per-queue drop counters named by the queue identifiers in
   -- the configuration.
   for _, queue in ipairs(conf.queues) do
      frame["rxdrop_"..queue.id] = {counter}
   end
   self.stats = shm.create_frame("pci/"..pciaddress, frame)

   -- Create separate HCAs to retreive port statistics.  Those
   -- commands must be called asynchronously to reduce latency.
   self.stats_reqs = {
      {
        start_fn = HCA.get_port_stats_start,
        finish_fn = HCA.get_port_stats_finish,
        process_fn = function (r, stats)
           local set = counter.set
           set(stats.rxbytes, r.rxbytes)
           set(stats.rxpackets, r.rxpackets)
           set(stats.rxmcast, r.rxmcast)
           set(stats.rxbcast, r.rxbcast)
           if self.mlx == 4 then
              -- ConnectX 4 doesn't have per-queue drop stats,
              -- but this counter appears to always be zero :/
              set(stats.rxdrop, r.rxdrop)
           end
           set(stats.rxerrors, r.rxerrors)
           set(stats.txbytes, r.txbytes)
           set(stats.txpackets, r.txpackets)
           set(stats.txmcast, r.txmcast)
           set(stats.txbcast, r.txbcast)
           set(stats.txdrop, r.txdrop)
           set(stats.txerrors, r.txerrors)
        end
      },
      {
        start_fn = HCA.get_port_speed_start,
        finish_fn = HCA.get_port_speed_finish,
        process_fn = function (r, stats)
           counter.set(stats.speed, r)
        end
      },
      {
        start_fn = HCA.get_port_status_start,
        finish_fn = HCA.get_port_status_finish,
        process_fn = function (r, stats)
           counter.set(stats.status, (r.oper_status == 1 and 1) or 2)
        end
      },
   }

   -- Empty for ConnectX4
   for _, q_counter in ipairs(q_counters) do
      local per_q_rxdrop = self.stats["rxdrop_"..q_counter.queue_id]
      table.insert(self.stats_reqs,
                   {
                      start_fn = HCA.query_q_counter_start,
                      finish_fn = HCA.query_q_counter_finish,
                      args = q_counter.counter_id,
                      process_fn = function(r, stats)
                         -- Incremental update relies on query_q_counter to
                         -- clear the counter after read.
                         counter.add(stats.rxdrop, r.out_of_buffer)
                         counter.add(per_q_rxdrop, r.out_of_buffer)
                      end
      })
   end

   for _, req in ipairs(self.stats_reqs) do
      req.hca = hca_factory:new()
      -- Post command
      req.start_fn(req.hca, req.args)
   end
   self.sync_timer = lib.throttle(conf.sync_stats_interval)

   function free_cxq (cxq)
      -- Force CXQ state -> DEAD
      local timeout = lib.timeout(2)
      lib.waitfor(function ()
         assert(not timeout(), "ConnectX: failed to close CXQ.")
         return sync.cas(cxq.state, IDLE, DEAD)
             or sync.cas(cxq.state, FREE, DEAD)
      end)
      -- Reclaim packets
      for idx=0, cxq.rqsize-1 do
         if cxq.rx[idx] ~= nil then
            packet.free(cxq.rx[idx])
            cxq.rx[idx] = nil
         end
      end
      for idx=0, cxq.sqsize-1 do
         if cxq.tx[idx] ~= nil then
            packet.free(cxq.tx[idx])
            cxq.tx[idx] = nil
         end
      end
   end

   function self:stop ()
      pci.set_bus_master(pciaddress, false)
      pci.reset_device(pciaddress)
      pci.close_pci_resource(fd, mmio)
      mmio, fd = nil
      for shmpath, cxq in pairs(cxq_shm) do
         free_cxq(cxq)
         shm.unlink(shmpath)
      end
      shm.delete_frame(self.stats)
   end

   function self:pull ()
      if self.sync_timer() then
         self:sync_stats()
         eq:poll()
      end
   end

   local last_stats = {
      rxpackets = 0,
      rxbytes = 0,
      txpackets = 0,
      txbytes = 0
   }
   function self:report ()
      self:sync_stats()
      local stats = self.stats
      local txpackets = counter.read(stats.txpackets) - last_stats.txpackets
      local txbytes = counter.read(stats.txbytes) - last_stats.txbytes
      local rxpackets = counter.read(stats.rxpackets) - last_stats.rxpackets
      local rxbytes = counter.read(stats.rxbytes) - last_stats.rxbytes
      last_stats.txpackets = counter.read(stats.txpackets)
      last_stats.txbytes = counter.read(stats.txbytes)
      last_stats.rxpackets = counter.read(stats.rxpackets)
      last_stats.rxbytes = counter.read(stats.rxbytes)
      print(pciaddress,
         "TX packets", lib.comma_value(tonumber(txpackets)),
         "TX bytes", lib.comma_value(tonumber(txbytes)))
      print(pciaddress,
         "RX packets", lib.comma_value(tonumber(rxpackets)),
         "RX bytes", lib.comma_value(tonumber(rxbytes)))
   end

   function self:sync_stats ()
      for _, req in ipairs(self.stats_reqs) do
         local hca = req.hca
         if hca:completed() then
            req.process_fn(req.finish_fn(hca), self.stats)
            hca:post()
         end
      end
   end

   -- Save "instance variable" values.
   self.hca = hca

   return self
end

function ConnectX:dump_capabilities (hca)
   --if true then return end
   -- Print current and maximum card capabilities.
   -- XXX Check if we have any specific requirements that we need to
   --     set and/or assert on.
   local cur = hca:query_hca_general_cap('current')
   local max = hca:query_hca_general_cap('max')
   print'Capabilities - current and (maximum):'
   for k in pairs(cur) do
      print(("  %-24s = %-3s (%s)"):format(k, cur[k], max[k]))
   end
end

function ConnectX:check_vport ()
   if true then return end
   local vport_ctx = hca:query_nic_vport_context()
   for k,v in pairs(vport_ctx) do
      print(k,v)
   end
   local vport_state = hca:query_vport_state()
   for k,v in pairs(vport_state) do
      print(k,v)
   end
end

function ConnectX:print_vport_counter ()
   local c = self.hca:query_vport_counter()
   local t = {}
   -- Sort into key order
   for k in pairs(c) do table.insert(t, k) end
   table.sort(t)
   for _, k in pairs(t) do
      print(("%12s %s"):format(lib.comma_value(c[k]), k))
   end
end

---------------------------------------------------------------
-- Firmware commands.
--
-- Code for sending individual messages to the firmware.
-- These messages are defined in the "Command Reference" section
-- of the Mellanox Programmer Reference Manual (PRM).
--
-- (See further below for the implementation of the command interface.)
---------------------------------------------------------------

-- These commands are all built on a handful of primitives for sending
-- commands to the HCA. The parameters to these functions are chosen
-- to be easy to cross-reference with the definitions in the PRM.
--
--   command(name, last_input_offset, last_output_offset)
--     Start preparing a command for the HCA.
--     The input and output sizes are given as the offsets of their
--     last dwords.
--     The command name is given only for debugging purposes.
--
--   input(name, offset, highbit, lowbit, value)
--     Specify an input parameter to the current command.
--     The parameter value is stored in the given bit-range at the
--     given offset.
--     The parameter name is given only for debugging purposes.
--
--    execute()
--      Execute the command specified starting with the most recent
--      call to command().
--      If the command fails then an exception is raised.
--
--    output(offset, highbit, lowbit)
--      Return a value from the output of the command.

-- Note: Parameters are often omitted when their default value (zero)
-- is sensible. Exceptions are made for more important ones.

-- hca object is the main interface towards the NIC firmware.
HCA = {}

-- Create a factory for HCAs for the given Initialization Segment
-- (i.e. device).  Application of the new() method to the returned
-- object allocates a new HCA for the next available Command Queue
-- Entry.
function HCA_factory (init_seg, cmdq_size)
   local self = {}
   self.size = 2^init_seg:log_cmdq_size()
   self.stride = 2^init_seg:log_cmdq_stride()
   self.init_seg = init_seg
   -- Next queue to be allocated by :new()
   self.nextq = 0
   local cmdq_size = cmdq_size or self.size
   assert(cmdq_size <= self.size, "command queue size limit exceeded")
   local cmdq_t = ffi.typeof("uint8_t (*)[$]", self.stride)
   local entries, entries_phy = memory.dma_alloc(cmdq_size * self.stride, 4096)
   self.entries = ffi.cast(cmdq_t, entries)
   init_seg:cmdq_phy_addr(entries_phy)
   return setmetatable(self, { __index = HCA })
end

---------------------------------------------------------------
-- Startup & General commands
---------------------------------------------------------------

-- Turn on the NIC.
function HCA:enable_hca ()
   self:command("ENABLE_HCA", 0x0C, 0x08)
      :input("opcode", 0x00, 31, 16, 0x104)
      :execute()
end

-- Initialize the NIC firmware.
function HCA:init_hca ()
   self:command("INIT_HCA", 0x0c, 0x0c)
      :input("opcode", 0x00, 31, 16, 0x102)
      :execute()
end

-- Set the software-firmware interface version to use.
function HCA:set_issi (issi)
   self:command("SET_ISSI", 0x0C, 0x0C)
      :input("opcode", 0x00, 31, 16, 0x10B)
      :input("issi",   0x08, 15,  0, issi)
      :execute()
end

-- Query the value of the "reserved lkey" for using physical addresses.
function HCA:query_rlkey ()
   self:command("QUERY_SPECIAL_CONTEXTS", 0x0C, 0x0C)
      :input("opcode", 0x00, 31, 16, 0x203)
      :execute()
   local rlkey = self:output(0x0C, 31, 0)
   return rlkey
end

-- Query how many pages of memory the NIC needs.
function HCA:query_pages (which)
   self:command("QUERY_PAGES", 0x0C, 0x0C)
      :input("opcode", 0x00, 31, 16, 0x107)
      :input("opmod",  0x04, 15,  0, ({boot=1,init=2,regular=3})[which])
      :execute()
   return self:output(0x0C, 31, 0)
end

-- Provide the NIC with freshly allocated memory.
function HCA:alloc_pages (num_pages)
   assert(num_pages > 0)
   if debug_info then
      print(("Allocating %d pages to HW"):format(num_pages))
   end
   self:command("MANAGE_PAGES", 0x14 + num_pages*8, 0x0C)
      :input("opcode",            0x00, 31, 16, 0x108)
      :input("opmod",             0x04, 15, 0, 1) -- allocate mode
      :input("input_num_entries", 0x0C, 31, 0, num_pages, "input_num_entries")
   for i=0, num_pages-1 do
      local _, phy = memory.dma_alloc(4096, 4096)
      self:input(nil, 0x10 + i*8, 31,  0, ptrbits(phy, 63, 32))
      self:input(nil, 0x14 + i*8, 31, 12, ptrbits(phy, 31, 12))
   end
   self:execute()
end

function HCA:free_pages (num_pages)
   assert(num_pages > 0)
   if debug_info then
      print(("Reclaiming %d pages from HW"):format(num_pages))
   end
   self:command("MANAGE_PAGES", 0x0C, 0x10 + num_pages*8)
      :input("opcode",            0x00, 31, 16, 0x108)
      :input("opmod",             0x04, 15, 0, 2) -- return pages
      :input("input_num_entries", 0x0C, 31, 0, num_pages, "input_num_entries")
      :execute()
   local num_entries = self:output(0x08, 31, 0)
   -- TODO: deallocate DMA pages
end

-- Query the NIC capabilities (maximum or current setting).
function HCA:query_hca_general_cap (max_or_current)
   local opmod = assert(({max=0, current=1})[max_or_current])
   self:command("QUERY_HCA_CAP", 0x0C, 0x100C - 3000)
      :input("opcode", 0x00, 31, 16, 0x100)
      :input("opmod",  0x04,  0,  0, opmod)
      :execute()
   return {
      log_max_cq_sz            = self:output(0x10 + 0x18, 23, 16),
      log_max_cq               = self:output(0x10 + 0x18,  4,  0),
      log_max_eq_sz            = self:output(0x10 + 0x1C, 31, 24),
      log_max_mkey             = self:output(0x10 + 0x1C, 21, 16),
      log_max_eq               = self:output(0x10 + 0x1C,  3,  0),
      max_indirection          = self:output(0x10 + 0x20, 31, 24),
      log_max_mrw_sz           = self:output(0x10 + 0x20, 22, 16),
      log_max_klm_list_size    = self:output(0x10 + 0x20,  5,  0),
      end_pad                  = self:output(0x10 + 0x2C, 31, 31),
      start_pad                = self:output(0x10 + 0x2C, 28, 28),
      cache_line_128byte       = self:output(0x10 + 0x2C, 27, 27),
      vport_counters           = self:output(0x10 + 0x30, 30, 30),
      vport_group_manager      = self:output(0x10 + 0x34, 31, 31),
      nic_flow_table           = self:output(0x10 + 0x34, 25, 25),
      port_type                = self:output(0x10 + 0x34,  9,  8),
      num_ports                = self:output(0x10 + 0x34,  7,  0),
      log_max_msg              = self:output(0x10 + 0x38, 28, 24),
      max_tc                   = self:output(0x10 + 0x38, 19, 16),
      cqe_version              = self:output(0x10 + 0x3C,  3,  0),
      cmdif_checksum           = self:output(0x10 + 0x40, 15, 14),
      wq_signature             = self:output(0x10 + 0x40, 11, 11),
      sctr_data_cqe            = self:output(0x10 + 0x40, 10, 10),
      eth_net_offloads         = self:output(0x10 + 0x40,  3,  3),
      cq_oi                    = self:output(0x10 + 0x44, 31, 31),
      cq_resize                = self:output(0x10 + 0x44, 30, 30),
      cq_moderation            = self:output(0x10 + 0x44, 29, 29),
      cq_eq_remap              = self:output(0x10 + 0x44, 25, 25),
      scqe_break_moderation    = self:output(0x10 + 0x44, 21, 21),
      cq_period_start_from_cqe = self:output(0x10 + 0x44, 20, 20),
      imaicl                   = self:output(0x10 + 0x44, 14, 14),
      xrc                      = self:output(0x10 + 0x44,  3,  3),
      ud                       = self:output(0x10 + 0x44,  2,  2),
      uc                       = self:output(0x10 + 0x44,  1,  1),
      rc                       = self:output(0x10 + 0x44,  0,  0),
      uar_sz                   = self:output(0x10 + 0x48, 21, 16),
      log_pg_sz                = self:output(0x10 + 0x48,  7,  0),
      bf                       = self:output(0x10 + 0x4C, 31, 31),
      driver_version           = self:output(0x10 + 0x4C, 30, 30),
      pad_tx_eth_packet        = self:output(0x10 + 0x4C, 29, 29),
      log_bf_reg_size          = self:output(0x10 + 0x4C, 20, 16),
      log_max_transport_domain = self:output(0x10 + 0x64, 28, 24),
      log_max_pd               = self:output(0x10 + 0x64, 20, 16),
      max_flow_counter         = self:output(0x10 + 0x68, 15,  0),
      log_max_rq               = self:output(0x10 + 0x6C, 28, 24),
      log_max_sq               = self:output(0x10 + 0x6C, 20, 16),
      log_max_tir              = self:output(0x10 + 0x6C, 12,  8),
      log_max_tis              = self:output(0x10 + 0x6C,  4,  0),
      basic_cyclic_rcv_wqe     = self:output(0x10 + 0x70, 31, 31),
      log_max_rmp              = self:output(0x10 + 0x70, 28, 24),
      log_max_rqt              = self:output(0x10 + 0x70, 20, 16),
      log_max_rqt_size         = self:output(0x10 + 0x70, 12,  8),
      log_max_tis_per_sq       = self:output(0x10 + 0x70,  4,  0),
      log_max_stride_sz_rq     = self:output(0x10 + 0x74, 28, 24),
      log_min_stride_sz_rq     = self:output(0x10 + 0x74, 20, 16),
      log_max_stride_sz_sq     = self:output(0x10 + 0x74, 12,  8),
      log_min_stride_sz_sq     = self:output(0x10 + 0x74,  4,  0),
      log_max_wq_sz            = self:output(0x10 + 0x78,  4,  0),
      log_max_vlan_list        = self:output(0x10 + 0x7C, 20, 16),
      log_max_current_mc_list  = self:output(0x10 + 0x7C, 12,  8),
      log_max_current_uc_list  = self:output(0x10 + 0x7C,  4,  0),
      log_max_l2_table         = self:output(0x10 + 0x90, 28, 24),
      log_uar_page_sz          = self:output(0x10 + 0x90, 15,  0),
      device_frequency_mhz     = self:output(0x10 + 0x98, 31,  0)
   }
end

-- Teardown the NIC firmware.
-- mode = 0 (graceful) or 1 (panic)
function HCA:teardown_hca (mode)
   self:command("TEARDOWN_HCA", 0x0c, 0x0c)
      :input("opcode", 0x00, 31, 16, 0x103)
      :input("opmod",  0x04, 15, 0, mode)
      :execute()
end

function HCA:disable_hca ()
   self:command("DISABLE_HCA", 0x0c, 0x0c)
      :input("opcode", 0x00, 31, 16, 0x105)
      :execute()
end

---------------------------------------------------------------
-- Event queues
---------------------------------------------------------------

-- Event Queue Entry (EQE)
local eqe_t = ffi.typeof([[
  struct {
    uint8_t  reserved1;
    uint8_t  event_type;
    uint8_t  reserved2;
    uint8_t  event_sub_type;
    uint32_t reserved3[7];
    uint32_t event_data[7];
    uint16_t reserved4;
    uint8_t  signature;
    uint8_t  owner;
  }
]])

-- Create an event queue that can be accessed via the given UAR page number.
function HCA:create_eq (uar)
   local numpages = 1
   local log_eq_size = 7 -- 128 entries
   local byte_size = 2^log_eq_size * ffi.sizeof(eqe_t)
   local ptr, phy = memory.dma_alloc(byte_size, 4096) -- memory for entries
   events = bits({
         CQError         = 0x04,
         PortStateChange = 0x09,
         PageRequest     = 0x0B,
   })
   self:command("CREATE_EQ", 0x10C + numpages*8, 0x0C)
      :input("opcode",        0x00,        31, 16, 0x301)
      :input("oi",            0x10 + 0x00, 17, 17, 1)   -- overrun ignore
      :input("log_eq_size",   0x10 + 0x0C, 28, 24, log_eq_size)
      :input("uar_page",      0x10 + 0x0C, 23,  0, uar)
      :input("log_page_size", 0x10 + 0x18, 28, 24, 2) -- XXX best value? 0 or max?
      :input("event bitmask", 0x5C, 31,  0, events)
      :input("pas[0] high",   0x110,       31,  0, ptrbits(phy, 63, 32))
      :input("pas[0] low",    0x114,       31,  0, ptrbits(phy, 31,  0))
      :execute()
   local eqn = self:output(0x08, 7, 0)
   return eq:new(eqn, ptr, log_eq_size, self)
end

eq = {}
eq.__index = eq

-- Create event queue object.
function eq:new (eqn, pointer, log_size, hca)
   local nentries = 2^log_size
   local ring = ffi.cast(ffi.typeof("$*", eqe_t), pointer)
   for i = 0, nentries - 1 do
      -- Owner = HW
      ring[i].owner = 1
   end
   local mask = nentries - 1
   return setmetatable({eqn = eqn,
                        ring = ring,
                        index = 0,
                        log_size = log_size,
                        mask = nentries - 1,
                        hca = hca,
                       },
      self)
end

function eq:sw_value ()
   return band(shr(self.index, self.log_size), 1)
end

function eq:entry ()
   local slot = band(self.index, self.mask)
   return self.ring[slot]
end

-- Poll the queue for events.
function eq:poll ()
   local eqe = self:entry()
   while eqe.owner == self:sw_value() do
      self:handle_event(eqe)
      self.index = self.index + 1
      eqe = self:entry()
   end
end

-- Handle an event.
local event_page_req = ffi.cdef([[
   struct event_page_req {
     uint16_t reserved1;
     uint16_t function_id;
     uint32_t num_pages;
     uint32_t reserved2[5];
   }
]])
local event_port_change = ffi.cdef([[
   struct event_port_change {
     uint32_t reserved1[2];
     uint8_t  port_num;
     uint8_t  reserved2[3];
     uint32_t reserved2[4];
   }
]])
local port_status = {
   [1] = "down",
   [4] = "up"
}
local event_cq_error = ffi.cdef([[
   struct event_cq_error {
     uint32_t cqn;
     uint32_t reserved1;
     uint8_t  reserved2[3];
     uint8_t  syndrome;
     uint32_t reserved3[4];
   }
]])
local cq_errors = {
   [1] = "overrun",
   [2] = "access violation"
}
function eq:handle_event (eqe)
   if eqe.event_type == 0x04 then
      local cq_error = cast(typeof("struct event_cq_error *"), eqe.event_data)
      local cqn = bswap(cq_error.cqn)
      error(("Error on completion queue #%d: %s"):format(cqn, cq_errors[cq_error.syndrome]))
   elseif eqe.event_type == 0x09 then
      if debug_info then
         local port_change = cast(typeof("struct event_port_change *"), eqe.event_data)
         local port = shr(port_change.port_num, 4)
         print(("Port %d changed state to %s"):format(port, port_status[eqe.event_sub_type]))
      end
   elseif eqe.event_type == 0xB then
      local page_req = cast(typeof("struct event_page_req *"), eqe.event_data)
      local num_pages = bswap(page_req.num_pages)
      if num_pages < 0 then
         num_pages = -num_pages
         self.hca:free_pages(num_pages)
      else
         self.hca:alloc_pages(num_pages)
      end
   else
      error(("Received unexpected event type 0x%02x, subtype 0x%02x"):format(eqe.event_type,
                                                                             eqe.event_sub_type))
   end
end

---------------------------------------------------------------
-- Vport
---------------------------------------------------------------

function HCA:set_vport_admin_state (up)
   self:command("MODIFY_VPORT_STATE", 0x0c, 0x0c)
      :input("opcode",      0x00, 31, 16, 0x751)
      :input("admin_state", 0x0C,  7,  4, up and 1 or 0)
      :execute()
end

function HCA:query_vport_state ()
   self:command("QUERY_VPORT_STATE", 0x0c, 0x0c)
      :input("opcode", 0x00, 31, 16, 0x750)
      :execute()
   return { admin_state = self:output(0x0C, 7, 4),
            oper_state  = self:output(0x0C, 3, 0) }
end

-- Convenience function
function HCA:linkup ()
   return self:query_vport_state().oper_state == 1
end

function HCA:query_vport_counter ()
   self:command("QUERY_VPORT_COUNTER", 0x1c, 0x20c)
      :input("opcode", 0x00, 31, 16, 0x770)
      :execute()
   local function get64 (offset)
      local hi = self:output(offset, 31, 0)
      local lo = self:output(offset + 4, 31, 0)
      return lo + (hi * 2^32)
   end
   return {
      rx_error_packets = get64(0x10),
      rx_error_octets  = get64(0x18),
      tx_error_packets = get64(0x20),
      tx_error_octets  = get64(0x28),
      rx_bcast_packets = get64(0x70),
      rx_bcast_octets  = get64(0x78),
      tx_bcast_packets = get64(0x80),
      tx_bcast_octets  = get64(0x88),
      rx_ucast_packets = get64(0x90),
      rx_ucast_octets  = get64(0x98),
      tx_ucast_packets = get64(0xA0),
      tx_ucast_octets  = get64(0xA8),
      rx_mcast_packets = get64(0xB0),
      rx_mcast_octets  = get64(0xB8),
      tx_mcast_packets = get64(0xC0),
      tx_mcast_octets  = get64(0xC8)
   }
end

function HCA:query_nic_vport_context ()
   self:command("QUERY_NIC_VPORT_CONTEXT", 0x0c, 0x10+0xFC)
      :input("opcode", 0x00, 31, 16, 0x754)
      :execute()
   local mac_hi = self:output(0x10+0xF4, 31, 0)
   local mac_lo = self:output(0x10+0xF8, 31, 0)
   local mac = macaddress:new(bit.tohex(mac_hi, 4) .. bit.tohex(mac_lo, 8))
   return { min_wqe_inline_mode = self:output(0x10+0x00, 26, 24),
            mtu = self:output(0x10+0x24, 15, 0),
            promisc_uc  = self:output(0x10+0xf0, 31, 31) == 1,
            promisc_mc  = self:output(0x10+0xf0, 30, 30) == 1,
            promisc_all = self:output(0x10+0xf0, 29, 29) == 1,
            permanent_address = mac }
end

function HCA:modify_nic_vport_context (mtu, promisc_uc, promisc_mc, promisc_all)
   self:command("MODIFY_NIC_VPORT_CONTEXT", 0x1FC, 0x0C)
      :input("opcode",       0x00, 31, 16, 0x755)
      :input("field_select", 0x0C, 31, 0, 0x50) -- MTU + promisc
      :input("mtu",          0x100 + 0x24, 15,  0, mtu)
      :input("promisc_uc",   0x100 + 0xF0, 31, 31, promisc_uc and 1 or 0)
      :input("promisc_mc",   0x100 + 0xF0, 30, 30, promisc_mc and 1 or 0)
      :input("promisc_all",  0x100 + 0xF0, 29, 29, promisc_all and 1 or 0)
      :execute()
end

---------------------------------------------------------------
-- TIR and TIS
---------------------------------------------------------------

-- Allocate a Transport Domain.
function HCA:alloc_transport_domain ()
   self:command("ALLOC_TRANSPORT_DOMAIN", 0x0c, 0x0c)
      :input("opcode", 0x00, 31, 16, 0x816)
      :execute(0x0C, 0x0C)
   return self:output(0x08, 23, 0)
end

-- Create a TIR (Transport Interface Receive) with direct dispatch (no hashing)
function HCA:create_tir_direct (rqn, transport_domain)
   self:command("CREATE_TIR", 0x10C, 0x0C)
      :input("opcode",           0x00,        31, 16, 0x900)
      :input("inline_rqn",       0x20 + 0x1C, 23, 0, rqn)
      :input("transport_domain", 0x20 + 0x24, 23, 0, transport_domain)
      :execute()
   return self:output(0x08, 23, 0)
end

-- Create a TIR with indirect dispatching (hashing) based on IPv4/IPv6
-- addresses and optionally TCP/UDP ports.
function HCA:create_tir_indirect (rqt, transport_domain, l3_proto, l4_proto)
   local l3_protos = {
      v4 = 0,
      v6 = 1
   }
   local l4_protos = {
      tcp = 0,
      udp = 1
   }
   local l3_proto = assert(l3_protos[l3_proto or 'v4'], "invalid l3 proto")
   self:command("CREATE_TIR", 0x10C, 0x0C)
      :input("opcode",           0x00,        31, 16, 0x900)
      :input("disp_type",        0x20 + 0x04, 31, 28, 1) -- indirect
   -- Symmetric hashing would sort src/dst ports prior to hashing to
   -- map bi-directional traffic to the same queue. We don't need that
   -- since flows are inherently uni-directional.
      :input("rx_hash_symmetric",0x20 + 0x20, 31, 31, 0) -- disabled
      :input("indirect_table",   0x20 + 0x20, 23,  0, rqt)
      :input("rx_hash_fn",       0x20 + 0x24, 31, 28, 2) -- toeplitz
      :input("transport_domain", 0x20 + 0x24, 23,  0, transport_domain)
      :input("l3_prot_type",     0x20 + 0x50, 31, 31, l3_proto)
   if l4_proto == nil then
      self:input("selected_fields",  0x20 + 0x50, 29,  0, 3) -- SRC/DST
   else
      l4_proto = assert(l4_protos[l4_proto or 'tcp'], "invalid l4 proto")
      self:input("l4_prot_type",     0x20 + 0x50, 30, 30, l4_proto)
         :input("selected_fields",  0x20 + 0x50, 29,  0, 15) -- SRC/DST/SPORT/DPORT
   end
   -- XXX Is random hash key a good solution?
   for i = 0x28, 0x4C, 4 do
      self:input("toeplitz_key["..((i-0x28)/4).."]", 0x20 + i, 31,  0, math.random(2^32))
   end
   self:execute()
   return self:output(0x08, 23, 0)
end

function HCA:create_rqt (rqlist)
   -- Problem: Hardware requires number of hash buckets to be a power of 2.
   -- Workaround: Setup max # hash buckets and fill with queues in a loop.
   self:command("CREATE_RQT", 0x20 + 0xF0 + 4*rqt_max_size, 0x0C)
      :input("opcode",          0x00,        31, 16, 0x916)
      :input("rqt_max_size",    0x20 + 0x14, 15,  0, rqt_max_size)
      :input("rqt_actual_size", 0x20 + 0x18, 15,  0, rqt_max_size)
   for i = 0, rqt_max_size-1 do
      self:input("rq_num["..i.."]", 0x20 + 0xF0 + i*4, 23, 0, rqlist[1 + (i % #rqlist)])
   end
   self:execute()
   return self:output(0x08, 23, 0)
end

-- Create TIS (Transport Interface Send)
function HCA:create_tis (prio, transport_domain)
   self:command("CREATE_TIS", 0x20 + 0x9C, 0x0C)
      :input("opcode",           0x00, 31, 16, 0x912)
      :input("prio",             0x20 + 0x00, 19, 16, prio)
      :input("transport_domain", 0x20 + 0x24, 23,  0, transport_domain)
      :execute()
   return self:output(0x08, 23, 0)
end

-- Allocate a UAR (User Access Region) i.e. a page of MMIO registers.
function HCA:alloc_uar ()
   self:command("ALLOC_UAR", 0x0C, 0x0C)
      :input("opcode", 0x00, 31, 16, 0x802)
      :execute()
   return self:output(0x08, 23, 0)
end

-- Allocate a Protection Domain.
function HCA:alloc_protection_domain ()
   self:command("ALLOC_PD", 0x0C, 0x0C)
      :input("opcode", 0x00, 31, 16, 0x800)
      :execute()
   return self:output(0x08, 23, 0)
end

-- Create a completion queue and return a completion queue object.
function HCA:create_cq (entries, uar_page, eqn, collapsed)
   local doorbell, doorbell_phy = memory.dma_alloc(16)
   -- Memory for completion queue entries
   local size = entries * 64
   local cqe, cqe_phy = memory.dma_alloc(size, 4096)
   local log_page_size = log2size(math.ceil(size/4096))
   ffi.fill(cqe, entries * 64, 0xFF)
   self:command("CREATE_CQ", 0x114, 0x0C)
      :input("opcode",        0x00,        31, 16, 0x400)
      :input("cc",            0x10 + 0x00, 20, 20, collapsed and 1 or 0)
      :input("oi",            0x10 + 0x00, 17, 17, 1)
      :input("log_cq_size",   0x10 + 0x0C, 28, 24, log2size(entries))
      :input("uar_page",      0x10 + 0x0C, 23,  0, uar_page)
      :input("c_eqn",         0x10 + 0x14,  7,  0, eqn)
      :input("log_page_size", 0x10 + 0x18, 28, 24, log_page_size)
      :input("db_addr high",  0x10 + 0x38, 31,  0, ptrbits(doorbell_phy, 63, 32))
      :input("db_addr_low",   0x10 + 0x3C, 31,  0, ptrbits(doorbell_phy, 31, 0))
      :input("pas[0] high",   0x110,       31,  0, ptrbits(cqe_phy, 63, 32))
      :input("pas[0] low",    0x114,       31,  0, ptrbits(cqe_phy, 31, 0))
      :execute()
   local cqn = self:output(0x08, 23, 0)
   return cqn, cqe
end

-- Create a receive queue and return a receive queue object.
-- Return the receive queue number and a pointer to the WQEs.
function HCA:create_rq (cqn, pd, stride, size, doorbell, rwq, counter_set_id)
   local log_wq_stride = log2size(stride)
   local log_wq_size = log2size(size)
   local db_phy = memory.virtual_to_physical(doorbell)
   local rwq_phy = memory.virtual_to_physical(rwq)
   local log_page_size = log2size(math.ceil(size * 64/4096))
   self:command("CREATE_RQ", 0x20 + 0x30 + 0xC4, 0x0C)
      :input("opcode",        0x00, 31, 16, 0x908)
      :input("rlkey",         0x20 + 0x00, 31, 31, 1)
      :input("vlan_strip_disable", 0x20 + 0x00, 28, 28, 1)
      :input("cqn",           0x20 + 0x08, 23, 0, cqn)
      :input("wq_type",       0x20 + 0x30 + 0x00, 31, 28, 1) -- cyclic
      :input("pd",            0x20 + 0x30 + 0x08, 23,  0, pd)
      :input("dbr_addr high", 0x20 + 0x30 + 0x10, 31,  0, ptrbits(db_phy, 63, 32))
      :input("dbr_addr low",  0x20 + 0x30 + 0x14, 31,  0, ptrbits(db_phy, 31, 0))
      :input("log_wq_stride", 0x20 + 0x30 + 0x20, 19, 16, log_wq_stride)
      :input("log_page_size", 0x20 + 0x30 + 0x20, 12,  8, log_page_size)
      :input("log_wq_size",   0x20 + 0x30 + 0x20,  4 , 0, log_wq_size)
      :input("pas[0] high",   0x20 + 0x30 + 0xC0, 63, 32, ptrbits(rwq_phy, 63, 32))
      :input("pas[0] low",    0x20 + 0x30 + 0xC4, 31,  0, ptrbits(rwq_phy, 31, 0))
   if counter_set_id then
      -- Only set for ConnectX5 and higher
      self:input("counter_set_id",0x20 + 0x0C, 31, 24, counter_set_id)
   end
   self:execute()
   return self:output(0x08, 23, 0)
end

-- Modify a Receive Queue by making a state transition.
function HCA:modify_rq (rqn, curr_state, next_state)
   self:command("MODIFY_RQ", 0x20 + 0x30 + 0xC4, 0x0C)
      :input("opcode",     0x00,        31, 16, 0x909)
      :input("curr_state", 0x08,        31, 28, curr_state)
      :input("rqn",        0x08,        27,  0, rqn)
      :input("next_state", 0x20 + 0x00, 23, 20, next_state)
      :execute()
end

-- Modify a Send Queue by making a state transition.
function HCA:modify_sq (sqn, curr_state, next_state)
   self:command("MODIFY_SQ", 0x20 + 0x30 + 0xC4, 0x0C)
      :input("opcode",     0x00,        31, 16, 0x905)
      :input("curr_state", 0x08,        31, 28, curr_state)
      :input("sqn",        0x08,        23, 0, sqn)
      :input("next_state", 0x20 + 0x00, 23, 20, next_state)
      :execute()
end

-- Create a Send Queue.
-- Return the send queue number and a pointer to the WQEs.
function HCA:create_sq (cqn, pd, stride, size, doorbell, swq, uar, tis)
   local log_wq_stride = log2size(stride)
   local log_wq_size = log2size(size)
   local db_phy = memory.virtual_to_physical(doorbell)
   local swq_phy = memory.virtual_to_physical(swq)
   self:command("CREATE_SQ", 0x20 + 0x30 + 0xC4, 0x0C)
      :input("opcode",         0x00,               31, 16, 0x904)
      :input("rlkey",          0x20 + 0x00,        31, 31, 1)
      :input("fre",            0x20 + 0x00,        29, 29, 1)
      :input("flush_in_error_en",   0x20 + 0x00,   28, 28, 1)
      :input("min_wqe_inline_mode", 0x20 + 0x00,   26, 24, 1)
      :input("cqn",            0x20 + 0x08,        23, 0, cqn)
      :input("tis_lst_sz",     0x20 + 0x20,        31, 16, 1)
      :input("tis",            0x20 + 0x2C,        23, 0, tis)
      :input("wq_type",        0x20 + 0x30 + 0x00, 31, 28, 1) -- cyclic
      :input("pd",             0x20 + 0x30 + 0x08, 23, 0, pd)
      :input("uar_page",       0x20 + 0x30 + 0x0C, 23, 0, uar)
      :input("pas[0] high",    0x20 + 0x30 + 0x10, 31, 0, ptrbits(db_phy, 63, 32))
      :input("pas[0] low",     0x20 + 0x30 + 0x14, 31, 0, ptrbits(db_phy, 31, 0))
      :input("log_wq_stride",  0x20 + 0x30 + 0x20, 19, 16, log_wq_stride)
      :input("log_wq_page_sz", 0x20 + 0x30 + 0x20, 12, 8,  6) -- XXX check
      :input("log_wq_size",    0x20 + 0x30 + 0x20, 4,  0,  log_wq_size)
      :input("pas[0] high",    0x20 + 0x30 + 0xC0, 31, 0, ptrbits(swq_phy, 63, 32))
      :input("pas[0] low",     0x20 + 0x30 + 0xC4, 31, 0, ptrbits(swq_phy, 31, 0))

      :execute()
   return self:output(0x08, 23, 0)
end

---------------------------------------------------------------
-- IO app: attach to transmit and receive queues.
---------------------------------------------------------------

IO = {}
IO.__index = IO
-- The IO module is the device driver in the sense of
-- lib.hardware.pci.device_info
driver = IO

IO.config = {
   pciaddress = {required=true},
   queue = {required=true},
   packetblaster = {default=false}
}

function IO:new (conf)
   local self = setmetatable({}, self)

   local pciaddress = pci.qualified(conf.pciaddress)
   local queue = conf.queue
   -- This is also done in Connectex4:new() but might not have
   -- happened yet.
   pci.unbind_device_from_linux(pciaddress)
   local fd = pci.open_pci_resource_unlocked(pciaddress, 0)
   local mmio = pci.map_pci_memory(fd)

   local online = false      -- True when queue is up and running
   local cxq                 -- shm object containing queue control information
   local sq                  -- SQ send queue object
   local rq                  -- RQ receive queue object
   local open_throttle =     -- Timer to throttle shm open attempts (10ms)
      lib.throttle(0.25)

   -- Close the queue mapping.
   local function close ()
      shm.unlink(self.backlink)
      shm.unmap(cxq)
      cxq = nil
   end

   -- Open the queue mapping.
   local function open ()
      local shmpath = "group/pci/"..pciaddress.."/"..queue
      self.backlink = "mellanox/"..pciaddress.."/"..queue
      if shm.exists(shmpath) then
         shm.alias(self.backlink, shmpath)
         cxq = shm.open(shmpath, cxq_t)
         if sync.cas(cxq.state, FREE, IDLE) then
            sq = SQ:new(cxq, mmio)
            rq = RQ:new(cxq)
         else
            close()             -- Queue was not FREE.
         end
      end
   end

   -- Return true on successful activation of the queue.
   local function activate ()
      -- If not open then make a request on a regular schedule.
      if cxq == nil and open_throttle() then
         open()
      end
      if cxq then
         -- Careful: Control app may have closed the CXQ.
         if sync.cas(cxq.state, IDLE, BUSY) then
            return true
         else
            assert(cxq.state[0] == DEAD, "illegal state detected")
            close()
         end
      end
   end

   -- Enter the idle state.
   local function deactivate ()
      assert(sync.cas(cxq.state, BUSY, IDLE))
   end

   -- Send packets to the NIC
   function self:push ()
      if activate() then
         sq:transmit(self.input.input or self.input.rx)
         sq:reclaim()
         deactivate()
      end
   end

   -- Receive packets from the NIC.
   function self:pull ()
      if activate() then
         rq:receive(self.output.output or self.output.tx)
         rq:refill()
         deactivate()
      end
   end

   -- Detach from the NIC.
   function self:stop ()
      if cxq then
         if not sync.cas(cxq.state, IDLE, FREE) then
            assert(cxq.state[0] == DEAD, "illegal state detected")
         end
         close()
      end
   end

   -- Configure self as packetblaster?
   if conf.packetblaster then
      self.push = nil
      self.pull = function (self)
         if activate() then
            sq:blast(self.input.input or self.input.rx)
            deactivate()
         end
      end
   end

   return self
end

---------------------------------------------------------------
-- Receive queue

RQ = {}

function RQ:new (cxq)
   local rq = {}

   local mask = cxq.rqsize - 1
   -- Return the queue slot for the given consumer counter for either
   -- the CQ or the WQ. This assumes that both queues have the same
   -- size.
   local function slot (cc)
      return band(cc, mask)
   end

   -- Refill with buffers
   function rq:refill ()
      local notify = false      -- have to notify NIC with doorbell ring?
      while cxq.rx[slot(cxq.next_rx_wqeid)] == nil do
         local p = packet.allocate()
         cxq.rx[slot(cxq.next_rx_wqeid)] = p
         local rwqe = cxq.rwq[slot(cxq.next_rx_wqeid)]
         local phy = memory.virtual_to_physical(p.data)
         rwqe.length = bswap(packet.max_payload)
         rwqe.lkey = bswap(cxq.rlkey)
         rwqe.dma_hi = bswap(tonumber(shr(phy, 32)))
         rwqe.dma_lo  = bswap(tonumber(band(phy, 0xFFFFFFFF)))
         cxq.next_rx_wqeid = cxq.next_rx_wqeid + 1
         notify = true
      end
      if notify then
         -- ring doorbell
         cxq.doorbell.receive = bswap(cxq.next_rx_wqeid)
      end
   end

   local log2_rqsize = log2size(cxq.rqsize)
   local function sw_owned ()
      -- The value of the ownership flag that indicates owned by SW for
      -- the current consumer counter is flipped every time the counter
      -- wraps around the receive queue.
      return band(shr(cxq.rx_cqcc, log2_rqsize), 1)
   end

   local function have_input ()
      local c = cxq.rcq[slot(cxq.rx_cqcc)]
      local owner = bit.band(1, c.u8[0x3F])
      return owner == sw_owned()
   end

   function rq:receive (l)
      local limit = engine.pull_npackets
      while limit > 0 and have_input() do
         -- Find the next completion entry.
         local c = cxq.rcq[slot(cxq.rx_cqcc)]
         limit = limit - 1
         -- Advance to next completion.
         -- Note: assumes sqsize == cqsize
         cxq.rx_cqcc = cxq.rx_cqcc + 1
         -- Decode the completion entry.
         local opcode = shr(c.u8[0x3F], 4)
         local len = bswap(c.u32[0x2C/4])
         local wqeid = shr(bswap(c.u32[0x3C/4]), 16)
         local idx = slot(wqeid)
         if band(opcode, 0xfd) == 0 then -- opcode == 0 or opcode == 2
            -- Successful receive
            local p = cxq.rx[idx]
            -- assert(p ~= nil)
            p.length = len
            link.transmit(l, p)
            cxq.rx[idx] = nil
         elseif opcode == 13 or opcode == 14 then
            -- Error on receive
            -- assert(cxq.rx[idx] ~= nil)
            packet.free(cxq.rx[idx])
            cxq.rx[idx] = nil
            local syndromes = {
               [0x1] = "Local_Length_Error",
               [0x4] = "Local_Protection_Error",
               [0x5] = "Work_Request_Flushed_Error",
               [0x6] = "Memory_Window_Bind_Error",
               [0x10] = "Bad_Response_Error",
               [0x11] = "Local_Access_Error",
               [0x12] = "Remote_Invalid_Request_Error",
               [0x13] = "Remote_Access_Error",
               [0x14] = "Remote_Operation_Error"
            }
            local syndrome = c.u8[0x37]
            error(("Got error. opcode=%d syndrome=0x%x message=%s")
               :format(opcode, syndrome, syndromes[syndromes]))
         else
            error(("Unexpected CQE opcode: %d (0x%x)"):format(opcode, opcode))
         end
      end
   end

   return rq
end

---------------------------------------------------------------
-- Send queue

SQ = {}

function SQ:new (cxq, mmio)
   local sq = {}
   -- Cast pointers to expected types
   local mmio = ffi.cast("uint8_t*", mmio)
   cxq.bf_next = ffi.cast("uint64_t*", mmio + (cxq.uar * 4096) + 0x800)
   cxq.bf_alt  = ffi.cast("uint64_t*", mmio + (cxq.uar * 4096) + 0x900)

   local mask = cxq.sqsize - 1
   -- Return the transmit queue slot for the given WQE ID.
   -- (Transmit queue is a smaller power of two than max WQE ID.)
   local function slot (wqeid)
      return band(wqeid, mask)
   end

   -- Transmit packets from the link onto the send queue.
   function sq:transmit (l)
      local start_wqeid = cxq.next_tx_wqeid
      local next_slot = slot(start_wqeid)
      while not link.empty(l) and cxq.tx[next_slot] == nil do
         local p = link.receive(l)
         local wqe = cxq.swq[next_slot]
         -- Store packet pointer so that we can free it later
         cxq.tx[next_slot] = p

         -- Construct a 64-byte transmit descriptor.
         -- This is in three parts: Control, Ethernet, Data.
         -- The Ethernet part includes some inline data.

         -- Control segment
         wqe.u32[0] = bswap(shl(cxq.next_tx_wqeid, 8) + 0x0A)
         wqe.u32[1] = bswap(shl(cxq.sqn, 8) + 4)
         wqe.u32[2] = bswap(shl(2, 2)) -- completion always
         -- Ethernet segment
         local ninline = 16
         wqe.u32[7] = bswap(shl(ninline, 16))
         ffi.copy(wqe.u8 + 0x1E, p.data, ninline)
         -- Send Data Segment (inline data)
         wqe.u32[12] = bswap(p.length - ninline)
         wqe.u32[13] = bswap(cxq.rlkey)
         local phy = memory.virtual_to_physical(p.data + ninline)
         wqe.u32[14] = bswap(tonumber(shr(phy, 32)))
         wqe.u32[15] = bswap(tonumber(band(phy, 0xFFFFFFFF)))
         -- Advance counters
         cxq.next_tx_wqeid = cxq.next_tx_wqeid + 1
         next_slot = slot(cxq.next_tx_wqeid)
      end
      -- Ring the doorbell if we enqueued new packets.
      if cxq.next_tx_wqeid ~= start_wqeid then
         local current_packet = slot(cxq.next_tx_wqeid + mask)
         cxq.doorbell.send = bswap(cxq.next_tx_wqeid)
         cxq.bf_next[0] = cxq.swq[current_packet].u64[0]
         -- Switch next/alternate blue flame register for next time
         cxq.bf_next, cxq.bf_alt = cxq.bf_alt, cxq.bf_next
      end
   end

   local next_reclaim = 0
   -- Free packets when their transmission is complete.
   function sq:reclaim ()
      local opcode = cxq.scq[0].u8[0x38]
      if opcode == 0x0A then
         local wqeid = shr(bswap(cxq.scq[0].u32[0x3C/4]), 16)
         while next_reclaim ~= slot(wqeid) do
            -- assert(cxq.tx[next_reclaim] ~= nil)
            packet.free(cxq.tx[next_reclaim])
            cxq.tx[next_reclaim] = nil
            next_reclaim = slot(next_reclaim + 1)
         end
      end
   end

   -- Packetblaster: blast packets from link out of send queue.
   function sq:blast (l)
      local kickoff = sq:blast_load(l)

      -- Get current send queue tail (hardware controlled)
      local opcode = cxq.scq[0].u8[0x38]
      if opcode == 0x0A then
         local wqeid = shr(bswap(cxq.scq[0].u32[0x3C/4]), 16)

         -- Keep send queue topped up
         local next_slot = slot(cxq.next_tx_wqeid)
         while next_slot ~= slot(wqeid) do
            local wqe = cxq.swq[next_slot]
            -- Update control segment
            wqe.u32[0] = bswap(shl(cxq.next_tx_wqeid, 8) + 0x0A)
            -- Advance counters
            cxq.next_tx_wqeid = cxq.next_tx_wqeid + 1
            next_slot = slot(cxq.next_tx_wqeid)
         end
      end

      if opcode == 0x0A or kickoff then
         -- Ring the doorbell
         local current_packet = slot(cxq.next_tx_wqeid + mask)
         cxq.doorbell.send = bswap(cxq.next_tx_wqeid)
         cxq.bf_next[0] = cxq.swq[current_packet].u64[0]
         -- Switch next/alternate blue flame register for next time
         cxq.bf_next, cxq.bf_alt = cxq.bf_alt, cxq.bf_next
      end
   end

   -- Packetblaster: load packets from link into send queue.
   local loaded = 0
   function sq:blast_load (l)
      while loaded < cxq.sqsize and not link.empty(l) do
         local p = link.receive(l)
         local next_slot = slot(cxq.next_tx_wqeid)
         local wqe = cxq.swq[next_slot]

         -- Construct a 64-byte transmit descriptor.
         -- This is in three parts: Control, Ethernet, Data.
         -- The Ethernet part includes some inline data.

         -- Control segment
         wqe.u32[0] = bswap(shl(cxq.next_tx_wqeid, 8) + 0x0A)
         wqe.u32[1] = bswap(shl(cxq.sqn, 8) + 4)
         wqe.u32[2] = bswap(shl(2, 2)) -- completion always
         -- Ethernet segment
         local ninline = 16
         wqe.u32[7] = bswap(shl(ninline, 16))
         ffi.copy(wqe.u8 + 0x1E, p.data, ninline)
         -- Send Data Segment (inline data)
         wqe.u32[12] = bswap(p.length - ninline)
         wqe.u32[13] = bswap(cxq.rlkey)
         local phy = memory.virtual_to_physical(p.data + ninline)
         wqe.u32[14] = bswap(tonumber(shr(phy, 32)))
         wqe.u32[15] = bswap(tonumber(band(phy, 0xFFFFFFFF)))
         -- Advance counters
         cxq.next_tx_wqeid = cxq.next_tx_wqeid + 1
         loaded = loaded + 1
         -- Kickoff?
         return loaded == cxq.sqsize
      end
   end

   return sq
end

NIC_RX = 0 -- Flow table type code for incoming packets
NIC_TX = 1 -- Flow table type code for outgoing packets

FLOW_TABLE = 1 -- Flow table entry destination_type for FLOW_TABLE
TIR = 2 -- Flow table entry destination_type for TIR

-- Create a flow table.
function HCA:create_flow_table (table_type, level, size)
   self:command("CREATE_FLOW_TABLE", 0x3C, 0x0C)
      :input("opcode",     0x00,        31, 16, 0x930)
      :input("table_type", 0x10,        31, 24, table_type)
      :input("level",      0x18 + 0x00, 23, 16, level or 0)
      :input("log_size",   0x18 + 0x00,  7,  0, math.ceil(math.log(size or 1024, 2)))
      :execute()
   local table_id = self:output(0x08, 23, 0)
   return table_id
end

-- Set table as root flow table.
function HCA:set_flow_table_root (table_id, table_type)
   self:command("SET_FLOW_TABLE_ROOT", 0x3C, 0x0C)
      :input("opcode",     0x00, 31, 16, 0x92F)
      :input("table_type", 0x10, 31, 24, table_type)
      :input("table_id",   0x14, 23,  0, table_id)
      :execute()
end

-- Create a "wildcard" flow group that does not inspect any fields.
function HCA:create_flow_group_wildcard (table_id, table_type, start_ix, end_ix)
   self:command("CREATE_FLOW_GROUP", 0x3FC, 0x0C)
      :input("opcode",                0x00, 31, 16, 0x933)
      :input("table_type",            0x10, 31, 24, table_type)
      :input("table_id",              0x14, 23,  0, table_id)
      :input("start_ix",              0x1C, 31,  0, start_ix)
      :input("end_ix",                0x24, 31,  0, end_ix) -- (inclusive)
      :input("match_criteria_enable", 0x3C,  7,  0, 0) -- match outer headers
      :execute()
   local group_id = self:output(0x08, 23, 0)
   return group_id
end

-- Set a "wildcard" flow table entry that does not match on any fields.
function HCA:set_flow_table_entry_wildcard (table_id, table_type, group_id,
                                            flow_index, dest_type, dest_id)
   self:command("SET_FLOW_TABLE_ENTRY", 0x40 + 0x300, 0x0C)
      :input("opcode",       0x00,         31, 16, 0x936)
      :input("opmod",        0x04,         15,  0, 0) -- new entry
      :input("table_type",   0x10,         31, 24, table_type)
      :input("table_id",     0x14,         23,  0, table_id)
      :input("flow_index",   0x20,         31,  0, flow_index)
      :input("group_id",     0x40 + 0x04,  31,  0, group_id)
      :input("action",       0x40 + 0x0C,  15,  0, 4) -- action = FWD_DST
      :input("dest_list_sz", 0x40 + 0x10,  23,  0, 1) -- destination list size
      :input("dest_type",    0x40 + 0x300, 31, 24, dest_type)
      :input("dest_id",      0x40 + 0x300, 23,  0, dest_id)
      :execute()
end

-- Create a flow group that inspects the ethertype and optionally protocol fields.
function HCA:create_flow_group_ip (table_id, table_type, start_ix, end_ix, l3_only)
   self:command("CREATE_FLOW_GROUP", 0x3FC, 0x0C)
      :input("opcode",                0x00, 31, 16, 0x933)
      :input("table_type",            0x10, 31, 24, table_type)
      :input("table_id",              0x14, 23,  0, table_id)
      :input("start_ix",              0x1C, 31,  0, start_ix)
      :input("end_ix",                0x24, 31,  0, end_ix) -- (inclusive)
      :input("match_criteria_enable", 0x3C,  7,  0, 1) -- match outer headers
      :input("match_ether",           0x40 + 0x04, 15, 0, 0xFFFF)
   if l3_only == nil then
      self:input("match_proto",           0x40 + 0x10, 31, 24, 0xFF)
   end
   self:execute()
   local group_id = self:output(0x08, 23, 0)
   return group_id
end

-- Set a flow table entry that matches on the ethertype for IPv4/IPv6
-- as well as optionally on TCP/UDP protocol/next-header.
function HCA:set_flow_table_entry_ip (table_id, table_type, group_id,
                                      flow_index, dest_type, dest_id, l3_proto, l4_proto)
   local ethertypes = {
      v4 = 0x0800,
      v6 = 0x86dd
   }
   local l4_protos = {
      udp = 17,
      tcp = 6
   }
   local type = assert(ethertypes[l3_proto], "invalid l3 proto")
   self:command("SET_FLOW_TABLE_ENTRY", 0x40 + 0x300, 0x0C)
      :input("opcode",       0x00,         31, 16, 0x936)
      :input("opmod",        0x04,         15,  0, 0) -- new entry
      :input("table_type",   0x10,         31, 24, table_type)
      :input("table_id",     0x14,         23,  0, table_id)
      :input("flow_index",   0x20,         31,  0, flow_index)
      :input("group_id",     0x40 + 0x04,  31,  0, group_id)
      :input("action",       0x40 + 0x0C,  15,  0, 4) -- action = FWD_DST
      :input("dest_list_sz", 0x40 + 0x10,  23,  0, 1) -- destination list size
      :input("match_ether",  0x40 + 0x40 + 0x04, 15, 0, type)
   if l4_proto ~= nil then
      local proto = assert(l4_protos[l4_proto], "invalid l4 proto")
      self:input("match_proto",  0x40 + 0x40 + 0x10, 31, 24, proto)
   end
   self:input("dest_type",    0x40 + 0x300, 31, 24, dest_type)
       :input("dest_id",      0x40 + 0x300, 23,  0, dest_id)
       :execute()
end

-- Create a DMAC+VLAN flow group.
function HCA:create_flow_group_macvlan (table_id, table_type, start_ix, end_ix, usevlan, mcast)
   local dmac = (mcast and macaddress:new("01:00:00:00:00:00"))
             or macaddress:new("ff:ff:ff:ff:ff:ff")
   self:command("CREATE_FLOW_GROUP", 0x3FC, 0x0C)
      :input("opcode",         0x00,        31, 16, 0x933)
      :input("table_type",     0x10,        31, 24, table_type)
      :input("table_id",       0x14,        23,  0, table_id)
      :input("start_ix",       0x1C,        31,  0, start_ix)
      :input("end_ix",         0x24,        31,  0, end_ix) -- (inclusive)
      :input("match_criteria", 0x3C,         7,  0, 1) -- match outer headers
      :input("dmac0",          0x40 + 0x08, 31,  0, bswap(dmac:subbits(0,32)))
      :input("dmac1",          0x40 + 0x0C, 31, 16, shr(bswap(dmac:subbits(32,48)), 16))
   if usevlan then 
      self:input("vlanid",         0x40 + 0x0C, 11,  0, 0xFFF) 
   end
   self:execute()
   local group_id = self:output(0x08, 23, 0)
   return group_id
end

-- Set a DMAC+VLAN flow table rule.
function HCA:set_flow_table_entry_macvlan (table_id, table_type, group_id,
                                           flow_index, dest_type, dest_id, dmac, vlanid, mcast)
   local dest_ids = (mcast and dest_id) or {dest_id}
   self:command("SET_FLOW_TABLE_ENTRY", 0x40 + 0x300 + 0x8*(#dest_ids-1), 0x0C)
      :input("opcode",       0x00,         31, 16, 0x936)
      :input("opmod",        0x04,         15,  0, 0) -- new entry
      :input("table_type",   0x10,         31, 24, table_type)
      :input("table_id",     0x14,         23,  0, table_id)
      :input("flow_index",   0x20,         31,  0, flow_index)
      :input("group_id",     0x40 + 0x04,  31,  0, group_id)
      :input("action",       0x40 + 0x0C,  15,  0, 4) -- action = FWD_DST
      :input("dest_list_sz", 0x40 + 0x10,  23,  0, #dest_ids) -- destination list size
      :input("dmac0",        0x40 + 0x48,  31,  0, bswap(dmac:subbits(0,32)))
      :input("dmac1",        0x40 + 0x4C,  31, 16, shr(bswap(dmac:subbits(32,48)), 16))
      :input("vlan",         0x40 + 0x4C,  11,  0, vlanid or 0)
      for i, dest_id in ipairs(dest_ids) do
         self:input("dest_type", 0x40 + 0x300 + 0x8*(i-1), 31, 24, dest_type)
         self:input("dest_id",   0x40 + 0x300 + 0x8*(i-1), 23,  0, dest_id)
      end
      self:execute()
end

---------------------------------------------------------------
-- PHY control access
---------------------------------------------------------------

-- Note: portnumber is always 1 because the ConnectX-4 HCA is managing
-- a single physical port.

PMTU  = 0x5003
PTYS  = 0x5004 -- Port Type and Speed
PAOS  = 0x5006 -- Port Administrative & Operational Status
PFCC  = 0x5007 -- Port Flow Control Configuration
PPCNT = 0x5008 -- Ports Performance Counters
PPLR  = 0x5018 -- Port Physical Loopback Register

-- Mapping of speed/protocols per 11.1.2 to speed in units of gbps
local port_speed = {
   [0x00000002] =   1, -- 1000Base-KX
   [0x00000004] =  10, --  10GBase-CX4
   [0x00000008] =  10, --  10GBase-KX4
   [0x00000010] =  10, --  10GBase-KR
   [0x00000040] =  40, --  40GBase-CR4
   [0x00000080] =  40, --  40GBase-KR4
   [0x00001000] =  10, --  10GBase-CR
   [0x00002000] =  10, --  10GBase-SR
   [0x00004000] =  10, --  10GBase-ER/LR
   [0x00008000] =  40, --  40GBase-SR4
   [0x00010000] =  40, --  40GBase-LR4/ER4
   [0x00040000] =  50, --  50GBase-SR2
   [0x00100000] = 100, -- 100GBase-CR4
   [0x00200000] = 100, -- 100GBase-SR4
   [0x00400000] = 100, -- 100GBase-KR4
   -- Undocumented (from a ConnectX5 NIC with CWDM plugin)
   [0x00800000] = 100, -- 100GBase-CWDM
   [0x08000000] =  25, --  25GBase-CR
   [0x10000000] =  25, --  25GBase-KR
   [0x20000000] =  25, --  25GBase-SR
   [0x40000000] =  50, --  50GBase-CR2
   [0x80000000] =  50, --  50GBase-KR2
}

-- Get the speed of the port in bps
function HCA:get_port_speed_start ()
   self:command("ACCESS_REGISTER", 0x4C, 0x4C)
      :input("opcode",       0x00, 31, 16, 0x805)
      :input("opmod",        0x04, 15,  0, 1) -- read
      :input("register_id",  0x08, 15,  0, PTYS)
      :input("local_port",   0x10, 23, 16, 1)
      :input("proto_mask",   0x10, 2,   0, 0x4) -- Ethernet
      :execute_async()
end

function HCA:get_port_speed_finish ()
   local eth_proto_oper = self:output(0x10 + 0x24, 31, 0)
   return (port_speed[eth_proto_oper] or 0) * 1e9
end

-- Set the administrative status of the port (boolean up/down).
function HCA:set_admin_status (admin_up)
   self:command("ACCESS_REGISTER", 0x1C, 0x0C)
      :input("opcode",       0x00, 31, 16, 0x805)
      :input("opmod",        0x04, 15,  0, 0) -- write
      :input("register_id",  0x08, 15,  0, PAOS)
      :input("local_port",   0x10, 23, 16, 1) -- 
      :input("admin_status", 0x10, 11,  8, admin_up and 1 or 2)
      :input("ase",          0x14, 31, 31, 1) -- enable admin state update
      :execute()
end

function HCA:set_port_mtu (mtu)
   self:command("ACCESS_REGISTER", 0x1C, 0x0C)
      :input("opcode", 0x00, 31, 16, 0x805)
      :input("opmod", 0x04, 15, 0, 0) -- write
      :input("register_id", 0x08, 15, 0, PMTU)
      :input("local_port",   0x10, 23, 16, 1)
      :input("admin_mtu", 0x18, 31, 16, mtu)
      :execute()
end

local port_status = { admin_status = 0, oper_status = 0 }
function HCA:get_port_status ()
   self:command("ACCESS_REGISTER", 0x10, 0x1C)
      :input("opcode", 0x00, 31, 16, 0x805)
      :input("opmod",  0x04, 15,  0, 1) -- read
      :input("register_id", 0x08, 15,  0, PAOS)
      :input("local_port", 0x10, 23, 16, 1)
      :execute()
   port_status.admin_status = self:output(0x10, 11, 8)
   port_status.oper_status = self:output(0x10, 3, 0)
   return port_status
end

function HCA:get_port_status_start ()
   self:command("ACCESS_REGISTER", 0x10, 0x1C)
      :input("opcode", 0x00, 31, 16, 0x805)
      :input("opmod",  0x04, 15,  0, 1) -- read
      :input("register_id", 0x08, 15,  0, PAOS)
      :input("local_port", 0x10, 23, 16, 1)
      :execute()
end

function HCA:get_port_status_finish ()
   port_status.admin_status = self:output(0x10, 11, 8)
   port_status.oper_status = self:output(0x10, 3, 0)
   return port_status
end

function HCA:get_port_loopback_capability ()
   self:command("ACCESS_REGISTER", 0x10, 0x14)
      :input("opcode",      0x00, 31, 16, 0x805)
      :input("opmod",       0x04, 15,  0, 1) -- read
      :input("register_id", 0x08, 15,  0, PPLR)
      :input("local_port",  0x10, 23, 16, 1)
      :execute()
   local capability = self:getoutbits(0x14, 23, 16)
   return capability
end

function HCA:set_port_loopback (loopback_mode)
   self:command("ACCESS_REGISTER", 0x14, 0x0C)
      :input("opcode",        0x00, 31, 16, 0x805)
      :input("opmod",         0x04, 15,  0, 0) -- write
      :input("register_id",   0x08, 15,  0, PPLR)
      :input("local_port",    0x10, 23, 16, 1)
      :input("loopback_mode", 0x14,  7,  0, loopback_mode and 2 or 0)
      :execute()
end

local port_stats = {
   rxbytes = 0ULL,
   rxmcast = 0ULL,
   rxbcast = 0ULL,
   rxpackets = 0ULL,
   rxdrop = 0ULL,
   rxerrors = 0ULL,
   txbytes = 0ULL,
   txmcast = 0ULL,
   txbcast = 0ULL,
   txpackets = 0ULL,
   txdrop = 0ULL,
   txerrors = 0ULL,
}
function HCA:get_port_stats_start ()
   self:command("ACCESS_REGISTER", 0x14, 0x10C)
      :input("opcode",        0x00, 31, 16, 0x805)
      :input("opmod",         0x04, 15,  0, 1) -- read
      :input("register_id",   0x08, 15,  0, PPCNT)
      :input("local_port",    0x10, 23, 16, 1)
      :input("grp",           0x10, 5, 0, 0x1) -- RFC 2863
      :execute_async()
end

function HCA:get_port_stats_finish ()
   port_stats.rxbytes = self:output64(0x18 + 0x00) -- includes 4-byte CRC
   local in_ucast_packets = self:output64(0x18 + 0x08)
   local in_mcast_packets = self:output64(0x18 + 0x48)
   local in_bcast_packets = self:output64(0x18 + 0x50)
   -- This is weird. The intel_mp driver adds broadcast packets to the
   -- mcast counter, it is unclear why.  Then
   -- lib.ipc.shmem.iftable_mib reverses it to get the true mcast
   -- counter back.  So we do the same here.  The proper fix would be
   -- to fix the Intel driver and remove the anti-hack from
   -- iftable_mib.
   port_stats.rxmcast = in_mcast_packets + in_bcast_packets
   port_stats.rxbcast = in_bcast_packets
   port_stats.rxpackets = in_ucast_packets + port_stats.rxmcast
   port_stats.rxdrop = self:output64(0x18 + 0x10)
   port_stats.rxerrors = self:output64(0x18 + 0x18)

   port_stats.txbytes = self:output64(0x18 + 0x28)
   local out_ucast_packets = self:output64(0x18 + 0x30)
   local out_mcast_packets = self:output64(0x18 + 0x58)
   local out_bcast_packets = self:output64(0x18 + 0x60)
   port_stats.txmcast = out_mcast_packets + out_bcast_packets
   port_stats.txbcast = out_bcast_packets
   port_stats.txpackets = out_ucast_packets + port_stats.txmcast
   port_stats.txdrop = self:output64(0x18 + 0x38)
   port_stats.txerrors = self:output64(0x18 + 0x40)
   return port_stats
end

function HCA:set_port_flow_control (rx_enable, tx_enable)
   self:command("ACCESS_REGISTER", 0x1C, 0x1C)
      :input("opcode", 0x00, 31, 16, 0x805)
      :input("opmod",  0x04, 15,  0, 0) -- write
      :input("register_id", 0x08, 15,  0, PFCC)
      :input("local_port", 0x10, 23, 16, 1)
      :input("pptx",       0x10 + 0x08, 31, 31, tx_enable and 1 or 0)
      :input("pprx",       0x10 + 0x0C, 31, 31, rx_enable and 1 or 0)
      :execute()
end

local fc_status = {}
function HCA:get_port_flow_control ()
   self:command("ACCESS_REGISTER", 0x10, 0x1C)
      :input("opcode", 0x00, 31, 16, 0x805)
      :input("opmod",  0x04, 15,  0, 1) -- read
      :input("register_id", 0x08, 15,  0, PFCC)
      :input("local_port", 0x10, 23, 16, 1)
      :execute()
   fc_status.pptx = self:output(0x10 + 0x08, 31, 31)
   fc_status.aptx = self:output(0x10 +0x08, 30, 30)
   fc_status.pfctx = self:output(0x10 + 0x08, 23, 16)
   fc_status.fctx_disabled = self:output(0x10 +0x08, 8, 8)
   fc_status.pprx = self:output(0x10 + 0x0c, 31, 31)
   fc_status.aprx = self:output(0x10 + 0x0c, 30, 30)
   fc_status.pfcrx = self:output(0x10 +0x0c, 23, 16)
   fc_status.stall_minor_watermark = self:output(0x10 +0x10, 31, 16)
   fc_status.stall_crit_watermark = self:output(0x10 +0x10, 15, 0)
   return fc_status
end

function HCA:alloc_q_counter()
   self:command("ALLOC_Q_COUNTER", 0x18, 0x10C)
      :input("opcode", 0x00, 31, 16, 0x771)
      :execute()
   return self:output(0x08, 7, 0)
end

local q_stats = {
   out_of_buffer = 0ULL
}
function HCA:query_q_counter_start (id)
   self:command("QUERY_Q_COUNTER", 0x20, 0x10C)
      :input("opcode",        0x00, 31, 16, 0x773)
   -- Clear the counter after reading. This allows us to
   -- update the rxdrop stat incrementally.
      :input("clear",         0x18, 31,  31, 1)
      :input("counter_set_id",0x1c,  7,   0, id)
      :execute_async()
end

local out_of_buffer = 0ULL
function HCA:query_q_counter_finish ()
   q_stats.out_of_buffer = self:output(0x10 + 0x20, 31, 0)
   return q_stats
end

---------------------------------------------------------------
-- Command Interface implementation.
--
-- Sends commands to the HCA firmware and receives replies.
-- Defined in "Command Interface" section of the PRM.
---------------------------------------------------------------

local cmdq_entry_t   = ffi.typeof("uint32_t[0x40/4]")
local cmdq_mailbox_t = ffi.typeof("uint32_t[0x240/4]")

-- XXX Check with maximum length of commands that we really use.
local max_mailboxes = 1000
local data_per_mailbox = 0x200 -- Bytes of input/output data in a mailbox

-- Create a command queue with dedicated/reusable DMA memory.
function HCA:new ()
   -- Must only be called from a factory created by HCA_factory()
   assert(self ~= HCA)
   local q = self.nextq
   assert(q < self.size)
   self.nextq = self.nextq + 1

   local inboxes, outboxes = {}, {}
   for i = 0, max_mailboxes-1 do
      -- XXX overpadding.. 0x240 alignment is not accepted?
      inboxes[i]  = ffi.cast("uint32_t*", memory.dma_alloc(0x240, 4096))
      outboxes[i] = ffi.cast("uint32_t*", memory.dma_alloc(0x240, 4096))
   end
   return setmetatable({entry = ffi.cast("uint32_t *", self.entries[q]),
                        inboxes = inboxes,
                        outboxes = outboxes,
                        q = q},
      {__index = self})
end

-- Reset all data structures to zero values.
-- This is to prevent leakage from one command to the next.
local token = 0xAA
function HCA:command (command, last_input_offset, last_output_offset)
   if debug_trace then
      print("HCA command: " .. command)
   end
   self.input_size  = last_input_offset + 4
   self.output_size = last_output_offset + 4

   -- Command entry:

   ffi.fill(self.entry, ffi.sizeof(cmdq_entry_t), 0)
   self:setbits(0x00, 31, 24, 0x7) -- type
   self:setbits(0x04, 31,  0, self.input_size)
   self:setbits(0x38, 31,  0, self.output_size)
   self:setbits(0x3C,  0,  0, 1) -- ownership = hardware
   self:setbits(0x3C, 31, 24, token)
   -- Mailboxes:

   -- How many mailboxes do we need?
   local ninboxes  = math.ceil((self.input_size  - 16) / data_per_mailbox)
   local noutboxes = math.ceil((self.output_size - 16) / data_per_mailbox)
   if ninboxes  > max_mailboxes then error("Input overflow: " ..self.input_size)  end
   if noutboxes > max_mailboxes then error("Output overflow: "..self.output_size) end

   if ninboxes > 0 then
      local phy = memory.virtual_to_physical(self.inboxes[0])
      setint(self.entry, 0x08, phy / 2^32)
      setint(self.entry, 0x0C, phy % 2^32)
   end
   if noutboxes > 0 then
      local phy = memory.virtual_to_physical(self.outboxes[0])
      setint(self.entry, 0x30, phy / 2^32)
      setint(self.entry, 0x34, phy % 2^32)
   end

   -- Initialize mailboxes
   for i = 0, max_mailboxes-1 do
      -- Zap old state
      ffi.fill(self.inboxes[i],  ffi.sizeof(cmdq_mailbox_t), 0)
      ffi.fill(self.outboxes[i], ffi.sizeof(cmdq_mailbox_t), 0)
      -- Set mailbox block number
      setint(self.inboxes[i],  0x238, i)
      setint(self.outboxes[i], 0x238, i)
      -- Tokens to match command entry
      setint(self.inboxes[i],  0x23C, setbits(23, 16, token, 0))
      setint(self.outboxes[i], 0x23C, setbits(23, 16, token, 0))
      -- Set 'next' mailbox pointers (when used)
      if i < ninboxes then
         local phy = memory.virtual_to_physical(self.inboxes[i+1])
         setint(self.inboxes[i], 0x230, phy / 2^32)
         setint(self.inboxes[i], 0x234, phy % 2^32)
      end
      if i < noutboxes then
         local phy = memory.virtual_to_physical(self.outboxes[i+1])
         setint(self.outboxes[i], 0x230, phy / 2^32)
         setint(self.outboxes[i], 0x234, phy % 2^32)
      end
   end
   token = (token == 255) and 1 or token+1
   return self -- for method call chaining
end

function HCA:getbits (offset, hi, lo)
   return getbits(getint(self.entry, offset), hi, lo)
end

function HCA:setbits (offset, hi, lo, value)
   local base = getint(self.entry, offset)
   setint(self.entry, offset, setbits(hi, lo, value, base))
end

function HCA:input (name, offset, hi, lo, value)
   assert(offset % 4 == 0)
   if debug_trace and name then
      print(("input @ %4xh (%2d:%2d) %-20s = %10xh (%d)"):format(offset, hi, lo, name, value, value))
   end
   if offset > self.input_size-4 then
      error(("input offset out of bounds: %sh > %sh"):format(
            bit.tohex(offset, 4), bit.tohex(self.input_size-4, 4)))
   end
   if offset <= 16 - 4 then -- inline
      self:setbits(0x10 + offset, hi, lo, value)
   else
      local mailbox_number = math.floor((offset - 16) / data_per_mailbox)
      local mailbox_offset = (offset - 16) % data_per_mailbox
      local base = getint(self.inboxes[mailbox_number], mailbox_offset)
      local newvalue = setbits(hi, lo, value, base)
      setint(self.inboxes[mailbox_number], mailbox_offset, newvalue)
   end
   return self -- for method call chaining
end

function HCA:output (offset, hi, lo)
   if offset <= 16 - 4 then --inline
      return self:getbits(0x20 + offset, hi, lo)
   else
      local mailbox_number = math.floor((offset - 16) / data_per_mailbox)
      local mailbox_offset  = (offset - 16) % data_per_mailbox
      return getbits(getint(self.outboxes[mailbox_number], mailbox_offset), hi, lo)
   end
end

function HCA:output64 (offset)
   local high = self:output(offset, 31, 0) + 0ULL
   local low = band(self:output(offset+4, 31, 0) + 0ULL, 0xFFFFFFFF)
   return shl(high, 32) + low
end



function HCA:setinbits (ofs, ...) --bit1, bit2, val, ...
   assert(ofs % 4 == 0)
   if ofs <= 16 - 4 then --inline
      self:setbits(0x10 + ofs, ...)
   else --input mailbox
      local mailbox = math.floor((ofs - 16) / data_per_mailbox)
      local offset = (ofs - 16) % data_per_mailbox
      setint(self.inboxes[mailbox], offset, setbits(...))
   end
end

function HCA:getoutbits (ofs, bit2, bit1)
   if ofs <= 16 - 4 then --inline
      return self:getbits(0x20 + ofs, bit2, bit1)
   else --output mailbox
      local mailbox = math.floor((ofs - 16) / data_per_mailbox)
      local offset  = (ofs - 16) % data_per_mailbox
      local b = getbits(getint(self.outboxes[mailbox], offset), bit2, bit1)
      return b
   end
end

-- "Command delivery status" error codes.
local delivery_errors = {
   [0x00] = 'no errors',
   [0x01] = 'signature error',
   [0x02] = 'token error',
   [0x03] = 'bad block number',
   [0x04] = 'bad output pointer. pointer not aligned to mailbox size',
   [0x05] = 'bad input pointer. pointer not aligned to mailbox size',
   [0x06] = 'internal error',
   [0x07] = 'input len error. input length less than 0x8',
   [0x08] = 'output len error. output length less than 0x8',
   [0x09] = 'reserved not zero',
   [0x10] = 'bad command type',
   -- Note: Suspicious to jump from 0x09 to 0x10 here i.e. skipping 0x0A - 0x0F.
   --       This is consistent with both the PRM and the Linux mlx5_core driver.
}

local function checkz (z)
   if z == 0 then return end
   error('command error: '..(delivery_errors[z] or z))
end

-- Command error code meanings.
-- Note: This information is missing from the PRM. Can compare with Linux mlx5_core.
local command_errors = {
   -- General:
   [0x01] = 'INTERNAL_ERR: internal error',
   [0x02] = 'BAD_OP: Operation/command not supported or opcode modifier not supported',
   [0x03] = 'BAD_PARAM: parameter not supported; parameter out of range; reserved not equal 0',
   [0x04] = 'BAD_SYS_STATE: System was not enabled or bad system state',
   [0x05] = 'BAD_RESOURCE: Attempt to access reserved or unallocated resource, or resource in inappropriate status. for example., not existing CQ when creating QP',
   [0x06] = 'RESOURCE_BUSY: Requested resource is currently executing a command. No change in any resource status or state i.e. command just not executed.',
   [0x08] = 'EXCEED_LIM: Required capability exceeds device limits',
   [0x09] = 'BAD_RES_STATE: Resource is not in the appropriate state or ownership',
   [0x0F] = 'NO_RESOURCES: Command was not executed because lack of resources (for example ICM pages). This is unrecoverable situation from driver point of view',
   [0x50] = 'BAD_INPUT_LEN: Bad command input len',
   [0x51] = 'BAD_OUTPUT_LEN: Bad command output len',
   -- QP/RQ/SQ/TIP:
   [0x10] = 'BAD_RESOURCE_STATE: Attempt to modify a Resource (RQ/SQ/TIP/QPs) which is not in the presumed state',
   -- MAD:
   [0x30] = 'BAD_PKT: Bad management packet (silently discarded)',
   -- CQ:
   [0x40] = 'BAD_SIZE: More outstanding CQEs in CQ than new CQ size',
}

function HCA:post ()
   self:setbits(0x3C, 0, 0, 1)
   self.init_seg:ring_doorbell(self.q)
end

function HCA:execute_async ()
   if debug_hexdump then
      local dumpoffset = 0
      print("command INPUT:")
      dumpoffset = hexdump(self.entry, 0, 0x40, dumpoffset)
      local ninboxes  = math.ceil((self.input_size + 4 - 16) / data_per_mailbox)
      for i = 0, ninboxes-1 do
         local blocknumber = getint(self.inboxes[i], 0x238, 31, 0)
         local address = memory.virtual_to_physical(self.inboxes[i])
         print("Block "..blocknumber.." @ "..bit.tohex(address, 12)..":")
         dumpoffset = hexdump(self.inboxes[i], 0, ffi.sizeof(cmdq_mailbox_t), dumpoffset)
      end
   end
   assert(self:getbits(0x3C, 0, 0) == 1)
   self:post()
end

function HCA:completed ()
   if self:getbits(0x3C, 0, 0) == 0 then
      if debug_hexdump then
         local dumpoffset = 0
         print("command OUTPUT:")
         dumpoffset = hexdump(self.entry, 0, 0x40, dumpoffset)
         local noutboxes = math.ceil((self.output_size + 4 - 16) / data_per_mailbox)
         for i = 0, noutboxes-1 do
            local blocknumber = getint(self.outboxes[i], 0x238, 31, 0)
            local address = memory.virtual_to_physical(self.outboxes[i])
            print("Block "..blocknumber.." @ "..bit.tohex(address, 12)..":")
            dumpoffset = hexdump(self.outboxes[i], 0, ffi.sizeof(cmdq_mailbox_t), dumpoffset)
         end
      end

      local token     = self:getbits(0x3C, 31, 24)
      local signature = self:getbits(0x3C, 23, 16)
      local status    = self:getbits(0x3C,  7,  1)

      checkz(status)
      self:checkstatus()

      return signature, token
   else
      if self.init_seg:getbits(0x1010, 31, 24) ~= 0 then
         error("HCA health syndrome: " .. bit.tohex(self.init_seg:getbits(0x1010, 31, 24)))
      end
      return nil, nil
   end
end

function HCA:execute ()
   self:execute_async()
   local signature, token = self:completed()
   --poll for command completion
   while not signature do
      C.usleep(10000)
      signature, token = self:completed()
   end
   return signature, token
end

-- see 12.2 Return Status Summary
function HCA:checkstatus ()
   local status = self:getoutbits(0x00, 31, 24)
   local syndrome = self:getoutbits(0x04, 31, 0)
   if status == 0 then return end
   error(string.format('status: 0x%x (%s), syndrome: 0x%x',
                       status, command_errors[status], syndrome))
end



---------------------------------------------------------------
-- Initialization segment access.
--
-- The initialization segment is a region of memory-mapped PCI
-- registers. This is an interface directly to the hardware and is
-- used for bootstrapping communication with the firmware (amongst
-- other things).
--
-- Described in the "Initialization Segment" section of the PRM.
---------------------------------------------------------------

InitializationSegment = {}

-- Create an initialization segment object.
-- ptr is a pointer to the memory-mapped registers.
function InitializationSegment:new (ptr)
   return setmetatable({ptr = cast('uint32_t*', ptr)}, {__index = InitializationSegment})
end

function InitializationSegment:getbits (offset, hi, lo)
   return getbits(getint(self.ptr, offset), hi, lo)
end

function InitializationSegment:setbits (offset, hi, lo, value)
   setint(self.ptr, offset, setbits(hi, lo, value, 0))
end

function InitializationSegment:fw_rev () --maj, min, subminor
   return
      self:getbits(0, 15, 0),
      self:getbits(0, 31, 16),
      self:getbits(4, 15, 0)
end

function InitializationSegment:cmd_interface_rev ()
   return self:getbits(4, 31, 16)
end

function InitializationSegment:cmdq_phy_addr (addr)
   if addr then
      --must write the MSB of the addr first
      self:setbits(0x10, 31, 0, ptrbits(addr, 63, 32))
      --also resets nic_interface and log_cmdq_*
      self:setbits(0x14, 31, 12, ptrbits(addr, 31, 12))
   else
      return cast('void*',
         cast('uint64_t', self:getbits(0x10, 31, 0) * 2^32 +
         cast('uint64_t', self:getbits(0x14, 31, 12)) * 2^12))
   end
end

function InitializationSegment:nic_interface (mode)
   self:setbits(0x14, 9, 8, mode)
end

function InitializationSegment:log_cmdq_size ()
   return self:getbits(0x14, 7, 4)
end

function InitializationSegment:log_cmdq_stride ()
   return self:getbits(0x14, 3, 0)
end

function InitializationSegment:ring_doorbell (i)
   self:setbits(0x18, i, i, 1)
end

function InitializationSegment:ready (i, val)
   return self:getbits(0x1fc, 31, 31) == 0
end

function InitializationSegment:nic_interface_supported ()
   return self:getbits(0x1fc, 26, 24) == 0
end

function InitializationSegment:internal_timer ()
   return
      self:getbits(0x1000, 31, 0) * 2^32 +
      self:getbits(0x1004, 31, 0)
end

function InitializationSegment:clear_int ()
   self:setbits(0x100c, 0, 0, 1)
end

function InitializationSegment:health_syndrome ()
   return self:getbits(0x1010, 31, 24)
end

function InitializationSegment:reset ()
   -- Not covered in PRM
   self:setbits(0x14, 10,  8, 0x7)
end

function InitializationSegment:dump ()
   print('fw_rev                  ', self:fw_rev())
   print('cmd_interface_rev       ', self:cmd_interface_rev())
   print('cmdq_phy_addr           ', self:cmdq_phy_addr())
   print('log_cmdq_size           ', self:log_cmdq_size())
   print('log_cmdq_stride         ', self:log_cmdq_stride())
   print('ready                   ', self:ready())
   print('nic_interface_supported ', self:nic_interface_supported())
   print('internal_timer          ', self:internal_timer())
   print('health_syndrome         ', self:health_syndrome())
end


---------------------------------------------------------------
-- Utilities.
---------------------------------------------------------------

-- Print a hexdump in the same format as the Linux kernel mlx5 driver.
-- 
-- Optionally take a 'dumpoffset' giving the logical address where the
-- trace starts (useful when printing multiple related hexdumps i.e.
-- for consistency with the Linux mlx5_core driver format).
function hexdump (pointer, index, bytes,  dumpoffset)
   local u8 = ffi.cast("uint8_t*", pointer)
   dumpoffset = dumpoffset or 0
   for i = 0, bytes-1 do
      if i % 16 == 0 then
         if i > 0 then io.stdout:write("\n") end
         io.stdout:write(("%03x: "):format(dumpoffset+i))
      elseif i % 4 == 0 then
         io.stdout:write(" ")
      end
      io.stdout:write(bit.tohex(u8[index+i], 2))
   end
   io.stdout:write("\n")
   io.flush()
   return dumpoffset + bytes
end

-- Utilities for peeking and poking bitfields of 32-bit big-endian integers.
-- Pointers are uint32_t* and offsets are in bytes.

-- Return the value at offset from address.
function getint (pointer, offset)
   assert(offset % 4 == 0, "offset not dword-aligned")
   local r = bswap(pointer[offset/4])
   return r
end

-- Set the the value at offset from address.
function setint (pointer, offset, value)
   assert(offset % 4 == 0, "offset not dword-aligned")
   pointer[offset/4] = bswap(tonumber(value))
end

-- Return the hi:lo bits of value.
function getbits (value, hi, lo)
   local mask = shl(2^(hi-lo+1)-1, lo)
   local r = shr(band(value, mask), lo)
   --print("getbits", bit.tohex(value), hi, lo, bit.tohex(r))
   return r
end

-- Return the hi:lo bits of a pointer.
function ptrbits (pointer, hi, lo)
   return tonumber(getbits(cast('uint64_t', pointer), hi, lo))
end

-- Set value in bits hi:lo of (optional) base.
function setbits (hi, lo, value,  base)
   base = base or 0
   local mask = shl(2^(hi-lo+1)-1, lo)
   local newbits = band(shl(value, lo), mask)
   local oldbits = band(base, bnot(mask))
   return bor(newbits, oldbits)
end

function log2size (size)
   -- Return log2 of size rounded up to nearest whole number.
   --
   -- Note: Lua provides only natural logarithm function (base e) built-in.
   --       See http://www.mathwords.com/c/change_of_base_formula.htm
   return math.ceil(math.log(size) / math.log(2))
end

function check_pow2 (num)
   return bit.band(num, num - 1) == 0
end

function selftest ()
   io.stdout:setvbuf'no'

   local pcidev0 = lib.getenv("SNABB_PCI_CONNECTX_0")
   local pcidev1 = lib.getenv("SNABB_PCI_CONNECTX_1")
   -- XXX check PCI device type
   if not pcidev0 then
      print("SNABB_PCI_CONNECTX_0 not set")
      os.exit(engine.test_skipped_code)
   end
   if not pcidev1 then
      print("SNABB_PCI_CONNECTX_1 not set")
      os.exit(engine.test_skipped_code)
   end

   local io0 = IO:new({pciaddress = pcidev0, queue = 'a'})
   local io1 = IO:new({pciaddress = pcidev1, queue = 'b'})
   io0.input  = { input = link.new('input0') }
   io0.output = { output = link.new('output0') }
   io1.input  = { input = link.new('input1') }
   io1.output = { output = link.new('output1') }
   -- Exercise the IO apps before the NIC is initialized.
   io0:pull() io0:push() io1:pull() io1:push()
   local nic0 = ConnectX:new(lib.parse({pciaddress = pcidev0, queues = {{id='a'}}}, ConnectX.config))
   local nic1 = ConnectX:new(lib.parse({pciaddress = pcidev1, queues = {{id='b'}}}, ConnectX.config))

   print("selftest: waiting for both links up")
   while (nic0.hca:query_vport_state().oper_state ~= 1) or
         (nic1.hca:query_vport_state().oper_state ~= 1) do
      C.usleep(1e6)
   end

   local bursts = 10000
   local each   = 100
   local octets = 100
   print(("Links up. Sending %s packets."):format(lib.comma_value(each*bursts)))

   for i = 1, bursts + 100 do
      for id, app in ipairs({io0, io1}) do
         if i <= bursts then
            for i = 1, each do
               local p = packet.allocate()
               ffi.fill(p.data, octets, 0)  -- zero packet
               local header = lib.hexundump("000000000001 000000000002 0800", 14)
               ffi.copy(p.data, header, #header)
               p.data[12] = 0x08 -- ethertype = 0x0800
               p.length = octets
               link.transmit(app.input.input, p)
            end
         end
         app:pull()
         app:push()
         while not link.empty(io0.output.output) do packet.free(link.receive(io0.output.output)) end
         while not link.empty(io1.output.output) do packet.free(link.receive(io1.output.output)) end
      end
   end
   print("link", "txpkt", "txbyte", "txdrop")
   local i0 = io0.input.input
   local i1 = io1.input.input
   local o0 = io0.output.output
   local o1 = io1.output.output
   print("send0", tonumber(counter.read(i0.stats.txpackets)), tonumber(counter.read(i0.stats.txbytes)), tonumber(counter.read(i0.stats.txdrop)))
   print("send1", tonumber(counter.read(i1.stats.txpackets)), tonumber(counter.read(i1.stats.txbytes)), tonumber(counter.read(i1.stats.txdrop)))
   print("recv0", tonumber(counter.read(o0.stats.txpackets)), tonumber(counter.read(o0.stats.txbytes)), tonumber(counter.read(o0.stats.txdrop)))
   print("recv1", tonumber(counter.read(o1.stats.txpackets)), tonumber(counter.read(o1.stats.txbytes)), tonumber(counter.read(o1.stats.txdrop)))

   -- print("payload snippets of first 5 packets")
   -- print("port0")
   -- for i = 1, 5 do
   --    local p = link.receive(o0)
   --    if p then print(p.length, lib.hexdump(ffi.string(p.data, math.min(32, p.length)))) end
   -- end
   -- print("port1")
   -- for i = 1, 5 do
   --    local p = link.receive(o1)
   --    if p then print(p.length, lib.hexdump(ffi.string(p.data, math.min(32, p.length)))) end
   -- end

   print()
   print(("%-16s  %20s  %20s"):format("hardware counter", pcidev0, pcidev1))
   print("----------------  --------------------  --------------------")

   local stat0 = nic0.hca:query_vport_counter()
   local stat1 = nic1.hca:query_vport_counter()

   -- Sort into key order
   local t = {}
   for k in pairs(stat0) do table.insert(t, k) end
   table.sort(t)
   for _, k in pairs(t) do
      print(("%-16s  %20s  %20s"):format(k, lib.comma_value(stat0[k]), lib.comma_value(stat1[k])))
   end

   nic0:stop()
   nic1:stop()
   io0:stop()
   io1:stop()

   if (stat0.tx_ucast_packets == bursts*each and stat0.tx_ucast_octets == bursts*each*octets and
       stat1.tx_ucast_packets == bursts*each and stat1.tx_ucast_octets == bursts*each*octets) then
      print("selftest: ok")
   else
      error("selftest failed: unexpected counter values")
   end
end
