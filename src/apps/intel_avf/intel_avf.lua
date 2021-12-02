-- intel_avf: Device driver that conforms to the Intel Adaptive Virtual
-- Function specification
-- https://www.intel.com/content/dam/www/public/us/en/documents/product-specifications/ethernet-adaptive-virtual-function-hardware-spec.pdf
-- pgXXX in the comments refers to that page in v1.0 of the specification, released Feb 2018

module(..., package.seeall)

local ffi         = require("ffi")
local lib         = require("core.lib")
local sync     = require("core.sync")
local macaddress  = require("lib.macaddress")
local pci         = require("lib.hardware.pci")
local register    = require("lib.hardware.register")
local tophysical  = core.memory.virtual_to_physical
local band, lshift, rshift, bor = bit.band, bit.lshift, bit.rshift, bit.bor
local transmit, receive, empty = link.transmit, link.receive, link.empty
local counter     = require("core.counter")
local shm         = require("core.shm")

local bits        = lib.bits
local C           = ffi.C

local MAC_ADDR_BYTE_LEN = 6

Intel_avf = {
   config = {
      pciaddr = { required=true },
      nqueues = {},
      vlan = {},
      macs = {default={}},
      ring_buffer_size = {default=2048}
   }
}

-- The `driver' variable is used as a reference to the driver class in
-- order to interchangeably use NIC drivers.
driver = Intel_avf

function Intel_avf:load_registers()
   local scalar_registers = [[
      VFGEN_RSTAT       0x00008800 -       RW   VF Reset Status
      VFINT_DYN_CTL0    0x00005C00 -       RW   VF Interrupt Dynamic Control Zero
      VF_ATQBAL         0x00007C00 -       RW   VF MailBox Transmit Queu e Base Address Low
      VF_ATQBAH         0x00007800 -       RW   VF MailBox Transmit Queue Base Address High
      VF_ATQLEN         0x00006800 -       RW   VF MailBox Transmit Queue Length
      VF_ATQH           0x00006400 -       RW   VF MailBox Transmit Head
      VF_ATQT           0x00008400 -       RW   VF MailBox Transmit Tail
      VF_ARQBAL         0x00006C00 -       RW   VF MailBox Receive Queue Base Address Low
      VF_ARQBAH         0x00006000 -       RW   VF MailBox Receive Queue Base Address High
      VF_ARQLEN         0x00008000 -       RW   VF MailBox Receive Queue Length
      VF_ARQH           0x00007400 -       RW   VF MailBox Receive Head
      VF_ARQT           0x00007000 -       RW   VF MailBox Receive Tail
   ]]

   -- VFINT_ITRN[n,m] is not handled well by lib.hardware.register
   local array_registers = [[
      VFINT_DYN_CTLN    0x00003800 +0x4*0..63      RW    VF Interrupt Dynamic Control N
      VFINT_ITR0        0x00004C00 +0x4*0..2       RW    VF Interrupt Throttling Zero
      QTX_TAIL          0x00000000 +0x4*0..255     RW    Transmit Queue Tail
      QRX_TAIL          0x00002000 +0x4*0..255     RW    Receive Queue Tail
   ]]
   register.define(scalar_registers, self.r, self.base)
   register.define_array(array_registers, self.r, self.base)
end

-- Section 2.1.2.1.2 & 2.1.2.2.2 pg12 & pg16
local rxdesc_t = ffi.typeof([[
   union {
      struct {
         uint64_t address;
         uint64_t pad1;
         uint64_t pad2;
         uint64_t pad3;
      } __attribute__((packed)) read;
      struct {
         uint64_t pad0;
         uint64_t status_err_type_len;
         uint64_t pad2;
         uint64_t pad3;
      } __attribute__((packed)) write;
   }
]])
local rxdesc_ptr_t = ffi.typeof("$ *", rxdesc_t)

-- section 2.2.2.2 pg22
local txdesc_t = ffi.typeof([[
   struct {
      uint64_t address;
      uint64_t cmd_type_offset_bsz;
   } __attribute__((packed))
]])
local txdesc_ptr_t = ffi.typeof("$ *", txdesc_t)

local queue_select_t = ffi.typeof([[
   struct {
      uint16_t vsi_id;
      uint16_t pad;
      uint32_t rx_queues;
      uint32_t tx_queues;
   } __attribute__((packed))
]])
local queue_select_ptr_t = ffi.typeof("$ *", queue_select_t)

local virtchnl_msg_t = ffi.typeof([[
   struct {
      uint64_t pad0;
      uint32_t opcode;
      int32_t status;
      uint32_t vfid;
   } __attribute__((packed))
]])
local virtchnl_msg_ptr_t = ffi.typeof("$ *", virtchnl_msg_t)

local virtchnl_txq_info_t = ffi.typeof([[
   struct {
      uint16_t vsi_id;
      uint16_t queue_id;
      uint16_t ring_len;
      uint16_t deprecated0;
      uint64_t dma_ring_addr;
      uint64_t deprecated1;
   } __attribute__((packed))
]])

local virtchnl_rxq_info_t = ffi.typeof([[
   struct {
      uint16_t vsi_id;
      uint16_t queue_id;
      uint32_t ring_len;
      uint16_t hdr_size;
      uint16_t deprecated0;
      uint32_t databuffer_size;
      uint32_t max_pkt_size;
      uint32_t pad0;
      uint64_t dma_ring_addr;
      uint32_t deprecated1;
      uint32_t pad1;
   } __attribute__((packed))
]])

local virtchnl_queue_pair_info_t = ffi.typeof([[
   struct {
      /* NOTE: vsi_id and queue_id should be indentical for both queues. */
      $ txq;
      $ rxq;
   } __attribute__((packed))
]], virtchnl_txq_info_t, virtchnl_rxq_info_t)

local virtchnl_queue_config_info_t = ffi.typeof([[
   struct {
      uint16_t vsi_id;
      uint16_t num_queue_pairs;
      uint32_t pad;
      $ qpair[1];
   } __attribute__((packed))
]], virtchnl_queue_pair_info_t)

local virtchnl_queue_config_info_ptr_t = ffi.typeof("$ *", virtchnl_queue_config_info_t)

local virtchnl_ether_addr_t = ffi.typeof[[
   struct {
      uint8_t addr[6]; // MAC_ADDR_BYTE_LEN
      uint8_t pad[2];
   } __attribute__((packed))
]]
local virtchnl_ether_addr_list_t = ffi.typeof([[
   struct {
      uint16_t vsi;
      uint16_t num_elements;
      $ list[1];
   } __attribute__((packed))
]], virtchnl_ether_addr_t)
local virtchnl_ether_addr_list_ptr_t = ffi.typeof("$ *", virtchnl_ether_addr_list_t)

local eth_stats_t = ffi.typeof([[
   struct {
        uint64_t rx_bytes;
        uint64_t rx_unicast;
        uint64_t rx_multicast;
        uint64_t rx_broadcast;
        uint64_t rx_discards;
        uint64_t rx_unknown_protocol;
        uint64_t tx_bytes;
        uint64_t tx_unicast;
        uint64_t tx_multicast;
        uint64_t tx_broadcast;
        uint64_t tx_discards;
        uint64_t tx_errors;
   } __attribute__((packed))
]])
local eth_stats_ptr_t = ffi.typeof("$ *", eth_stats_t)

local virtchnl_vf_resources_t = ffi.typeof([[
   struct {
      uint16_t num_vsis;
      uint16_t num_queue_pairs;
      uint16_t max_vectors;
      uint16_t max_mtu;
      uint32_t vf_offload_flag;
      uint32_t rss_key_size;
      uint32_t rss_lut_size;

      uint16_t vsi_id;
      uint16_t vsi_queue_pairs;
      uint32_t vsi_type;
      uint16_t qset_handle;
      uint8_t default_mac_addr[6];
   } __attribute__((packed))
]])
local virtchnl_vf_resources_ptr_t = ffi.typeof('$*', virtchnl_vf_resources_t)

local virtchnl_version_t = ffi.typeof([[
   struct {
      uint32_t major;
      uint32_t minor;
   } __attribute__((packed))
]])
local virtchnl_version_ptr_t = ffi.typeof('$*', virtchnl_version_t)

local virtchnl_irq_map_info_t = ffi.typeof([[
   struct {
      uint16_t num_vectors;

      uint16_t vsi_id;
      uint16_t vector_id;
      uint16_t rxq_map;
      uint16_t txq_map;
      uint16_t rxitr_idx;
      uint16_t txitr_idx;
   } __attribute__((packed))
]])
local virtchnl_irq_map_info_ptr_t = ffi.typeof('$*', virtchnl_irq_map_info_t)

local virtchnl_rss_key_t = ffi.typeof([[
   struct {
      uint16_t vsi_id;
      uint16_t key_len;
      uint8_t key[1]; /* RSS hash key, packed bytes */
      uint8_t pad;
   } __attribute__((packed))
]])
local virtchnl_rss_key_ptr_t = ffi.typeof('$*', virtchnl_rss_key_t)

local virtchnl_rss_lut_t = ffi.typeof([[
   struct {
      uint16_t vsi_id;
      uint16_t lut_entries;
      uint8_t lut[1]; /* RSS lookup table*/
      uint8_t pad;
   } __attribute__((packed))
]])
local virtchnl_rss_lut_ptr_t = ffi.typeof('$*', virtchnl_rss_lut_t)

local virtchnl_rss_hena_t = ffi.typeof([[
   struct {
      uint64_t hena;
   } __attribute__((packed))
]])
local virtchnl_rss_hena_ptr_t = ffi.typeof('$*', virtchnl_rss_hena_t)

local virtchnl_vlan_filter_list_t = ffi.typeof([[
   struct {
      uint16_t vsi_id;
      uint16_t num_elements;
      uint16_t vlan_id[1];
   } __attribute__((packed))
]])
local virtchnl_vlan_filter_list_ptr_t = ffi.typeof('$*', virtchnl_vlan_filter_list_t)

local mbox_q_t = ffi.typeof([[
      struct {
         uint8_t flags0;
         uint8_t flags1;
         uint16_t opcode;
         uint16_t datalen;
         uint16_t return_value;
         uint32_t cookie_high;
         uint32_t cookie_low;
         uint32_t param0;
         uint32_t param1;
         uint32_t data_addr_high;
         uint32_t data_addr_low;
      } __attribute__((packed))
]])
local mbox_q_ptr_t = ffi.typeof('$*', mbox_q_t)

---------------------------------------------------------------
-- CXQ (Queue pair control object):
-- 
-- A "CXQ" is an object that we define to represent a transmit/receive pair.
-- 
-- CXQs are created and deleted by a "Control" app (Intel_avf) and,
-- in between, they are used by "IO" apps to send and receive packets.
-- 
-- The lifecycle of a CXQ is managed using a state machine. This is
-- necessary because we allow Control and IO apps to start in any
-- order, for Control and IO apps to start/stop/restart independently,
-- for multiple IO apps to attempt to attach to the same CXQ, and even
-- for apps to stop in one Snabb process and be started in another
-- one.
-- 
-- (This design is lifted from the apps.mellanox.connectx driver.)
--
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
--
--   Abnormal shutdown of the process hosting the Control app is *not*
--   supported. We just don’t have anywhere to free packets to in that
--   case.

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
      uint32_t qno;       // queue number
      uint16_t vlan;      // 802.1Q vlan tag
      uint32_t ring_size; // size of rx/tx rings

      // Transmit state
      uint32_t tx_next;
      uint32_t tx_cand;
      uint32_t tx_desc_free;
      $ txdesc;
      struct packet *txqueue[64*1024];

      // Receive state
      uint32_t rx_tail;
      $ rxdesc;
      struct packet *rxqueue[64*1024];
   } __attribute((packed))
]], txdesc_ptr_t, rxdesc_ptr_t)

-- CXQ states:
local INIT = 0 -- Implicit initial state due to 0 value.
local BUSY = 1
local IDLE = 2
local FREE = 3
local DEAD = 4

-- Release CXQ from IO apps after process termination.
-- Called from core.main.shutdown
function shutdown(pid)
   for _, pciaddr in ipairs(shm.children("/"..pid.."/intel_avf")) do
      for _, queue in ipairs(shm.children("/"..pid.."/intel_avf/"..pciaddr)) do
         local backlink = "/"..pid.."/intel_avf/"..pciaddr.."/"..queue
         local ok, cxq = pcall(shm.open, backlink, cxq_t)
         if ok then
            -- Allow reclaimation of CXQ
            sync.cas(cxq.state, IDLE, FREE)
            sync.cas(cxq.state, BUSY, FREE)
            shm.unlink(backlink)
         end
      end
   end
end

function Intel_avf:init_cxq (qno)
   -- Create a shared memory object for controlling the queue pair
   local cxq = shm.create("group/pci/"..self.pciaddress.."/"..qno, cxq_t)
   cxq.qno = qno
   cxq.vlan = self.vlan or 0
   cxq.ring_size = self.ring_buffer_size
   self:init_tx_q(cxq)
   self:init_rx_q(cxq)
   return cxq
end

function Intel_avf:free_cxq (cxq)
   -- Free packets remaining in TX/RX queues.
   for i = 0, cxq.ring_size-1 do
      if cxq.txqueue[i] ~= nil then
         packet.free(cxq.txqueue[i])
      end
      packet.free(cxq.rxqueue[i])
   end
   shm.unlink("group/pci/"..self.pciaddress.."/"..cxq.qno)
   shm.unmap(cxq)
end

function Intel_avf:init_tx_q(cxq)
   cxq.txdesc = ffi.cast(txdesc_ptr_t, memory.dma_alloc(ffi.sizeof(txdesc_t) * self.ring_buffer_size))
   ffi.fill(cxq.txdesc, ffi.sizeof(txdesc_t) * self.ring_buffer_size)
   for i=0, self.ring_buffer_size - 1 do
      cxq.txqueue[i] = nil
      cxq.txdesc[i].cmd_type_offset_bsz = 0
   end
   cxq.tx_next = 0
   cxq.tx_cand = 0
   cxq.tx_desc_free = self.ring_buffer_size - 1
end

function Intel_avf:init_rx_q(cxq)
   cxq.rxdesc = ffi.cast(rxdesc_ptr_t, memory.dma_alloc(ffi.sizeof(rxdesc_t) * self.ring_buffer_size))
   for i = 0, self.ring_buffer_size-1 do
      local p = packet.allocate()
      cxq.rxqueue[i] = p
      cxq.rxdesc[i].read.address = tophysical(p.data)
      cxq.rxdesc[i].write.status_err_type_len = 0
   end
   cxq.rx_tail = 0
end

function Intel_avf:supported_hardware()
   local vendor = lib.firstline(self.path .. "/vendor")
   local device = lib.firstline(self.path .. "/device")
   local devices = {
      -- Ethernet controller [0200]: Intel Corporation Ethernet Virtual Function 700 Series [8086:154c] (rev 02)
      "0x154c",
      -- pg8
      "0x1889"
   }
   assert(vendor == '0x8086', "unsupported nic vendor: " .. vendor)

   for _,v in pairs(devices) do
      if device == v then return end
   end
   assert(devices[device] == true, "unsupported nic version: " .. device)
end

function Intel_avf:mbox_allocate_rxq()
   -- new() allocates everything then resets the nic.
   -- Only allocate space the first time around
   if self.mbox.rxq ~= nil then
      return
   end
   self.mbox.rxq =
      memory.dma_alloc(self.mbox.q_byte_len, self.mbox.q_alignment)
   ffi.fill(self.mbox.rxq, self.mbox.q_byte_len)
   self.mbox.rxq = ffi.cast(mbox_q_ptr_t, self.mbox.rxq)

   for i=0,self.mbox.q_len-1 do
      local ptr = ffi.cast("uint8_t *", memory.dma_alloc(self.mbox.datalen))
      ffi.fill(ptr, self.mbox.datalen)

      self.mbox.rxq_buffers[i] = ptr

      self.mbox.rxq[i].data_addr_high =
         tophysical(self.mbox.rxq_buffers[i]) / 2^32

      self.mbox.rxq[i].data_addr_low =
         tophysical(self.mbox.rxq_buffers[i]) % 2^32

      self.mbox.rxq[i].datalen = self.mbox.datalen
      self.mbox.rxq[i].flags0 = 0
      self.mbox.rxq[i].flags1 =
         bits({LARGE_BUFFER = 1, BUFFER=4, NO_INTERRUPTS=5})
   end
end
function Intel_avf:mbox_setup_rxq()
   self:mbox_allocate_rxq()
   self.r.VF_ARQBAL(tophysical(self.mbox.rxq) % 2^32)
   self.r.VF_ARQBAH(tophysical(self.mbox.rxq) / 2^32)
   self.r.VF_ARQH(0)
   self.r.VF_ARQT(self.mbox.q_len-1)
   self.mbox.next_recv_idx = 0
   C.full_memory_barrier()

   -- set length and enable the queue
   self.r.VF_ARQLEN(bits({ ENABLE = 31 }) + self.mbox.q_len)
end

function Intel_avf:mbox_allocate_txq()
   if self.mbox.txq ~= nil then
      return
   end
   self.mbox.txq = memory.dma_alloc(self.mbox.q_byte_len, self.mbox.q_alignment)
   ffi.fill(self.mbox.txq, self.mbox.q_byte_len)
   self.mbox.txq = ffi.cast(mbox_q_ptr_t, self.mbox.txq)

   for i=0,self.mbox.q_len-1 do
      local ptr = ffi.cast("uint8_t *", memory.dma_alloc(4096))

      self.mbox.txq_buffers[i] = ptr

      self.mbox.txq[i].data_addr_high =
      tophysical(self.mbox.txq_buffers[i]) / 2^32

      self.mbox.txq[i].data_addr_low =
      tophysical(self.mbox.txq_buffers[i]) % 2^32
   end
end
function Intel_avf:mbox_setup_txq()
   self:mbox_allocate_txq()
   self.r.VF_ATQBAL(tophysical(self.mbox.txq) % 2^32)
   self.r.VF_ATQBAH(tophysical(self.mbox.txq) / 2^32)
   self.r.VF_ATQH(0)
   self.r.VF_ATQT(0)
   self.mbox.next_send_idx = 0
   C.full_memory_barrier()

   -- set length and enable the queue
   self.r.VF_ATQLEN(bits({ ENABLE = 31 }) + self.mbox.q_len)
end

function Intel_avf:mbox_sr_q(cxqs)
   local tt = self:mbox_send_buf(virtchnl_queue_config_info_ptr_t)

   tt.vsi_id = self.vsi_id
   tt.num_queue_pairs = #cxqs

   for i, cxq in ipairs(cxqs) do
      tt.qpair[i-1].txq.vsi_id = self.vsi_id
      tt.qpair[i-1].txq.queue_id = cxq.qno
      tt.qpair[i-1].txq.ring_len = cxq.ring_size
      tt.qpair[i-1].txq.dma_ring_addr = tophysical(cxq.txdesc)

      tt.qpair[i-1].rxq.vsi_id = self.vsi_id
      tt.qpair[i-1].rxq.queue_id = cxq.qno
      tt.qpair[i-1].rxq.ring_len = cxq.ring_size
      -- Only 32 byte rxdescs are supported, at least by the PF driver in
      -- centos 7 3.10.0-957.1.3.el7.x86_64
      tt.qpair[i-1].rxq.hdr_size = 32
      tt.qpair[i-1].rxq.databuffer_size = packet.max_payload
      tt.qpair[i-1].rxq.max_pkt_size = packet.max_payload
      tt.qpair[i-1].rxq.dma_ring_addr = tophysical(cxq.rxdesc)
   end

   self:mbox_sr('VIRTCHNL_OP_CONFIG_VSI_QUEUES',
                ffi.sizeof(virtchnl_queue_config_info_t) +
                ffi.sizeof(virtchnl_queue_pair_info_t) * #cxqs)
end

function Intel_avf:mbox_sr_enable_q (nqueues)
   local tt = self:mbox_send_buf(queue_select_ptr_t)

   tt.vsi_id = self.vsi_id
   tt.pad = 0
   local q_enable_mask = lshift(1, nqueues) - 1
   tt.rx_queues = q_enable_mask
   tt.tx_queues = q_enable_mask
   self:mbox_sr('VIRTCHNL_OP_ENABLE_QUEUES', ffi.sizeof(queue_select_t))
end

IO = {
   config = {
      pciaddr = {required=true},
      queue = {required=true}
   }
}

function IO:new (conf)
   local self = setmetatable({}, { __index = IO })
   self.pciaddr = pci.qualified(conf.pciaddr)
   self.qno = conf.queue

   -- This is also done in Intel_avf:new() but might not have
   -- happened yet.
   pci.unbind_device_from_linux(self.pciaddr)

   self.fd = pci.open_pci_resource_unlocked(self.pciaddr, 0)
   self.base = pci.map_pci_memory(self.fd)
   self.r = {}
   Intel_avf.load_registers(self) -- Initialize registers at (self.r.*)

   self.online = false      -- True when queue is up and running
   self.cxq = nil           -- shm object containing queue control information
   self.open_throttle =     -- Timer to throttle shm open attempts (10ms)
      lib.throttle(0.25)

   return self
end

function IO:stop()
   if self.cxq then
      assert(sync.cas(self.cxq.state, IDLE, FREE) or
               self.cxq.state[0] == DEAD,
            "illegal state detected")
      self:close()
   end
end

-- Close the queue mapping.
function IO:close ()
   shm.unlink(self.backlink)
   shm.unmap(self.cxq)
   self.cxq = nil
end

-- Open the queue mapping.
function IO:open ()
   local shmpath = "group/pci/"..self.pciaddr.."/"..self.qno
   self.backlink = "intel_avf/"..self.pciaddr.."/"..self.qno
   if shm.exists(shmpath) then
      shm.alias(self.backlink, shmpath)
      self.cxq = shm.open(shmpath, cxq_t)
      if sync.cas(self.cxq.state, FREE, IDLE) then
         -- Select queue tail registers
         self.r.rx_tail = self.r.QRX_TAIL[self.cxq.qno]
         self.r.tx_tail = self.r.QTX_TAIL[self.cxq.qno]
      else
         close()             -- Queue was not FREE.
      end
   end
end

-- Return true on successful activation of the queue.
function IO:activate ()
   -- If not open then make a request on a regular schedule.
   if self.cxq == nil and self.open_throttle() then
      self:open()
   end
   if self.cxq then
      -- Careful: Control app may have closed the CXQ.
      if sync.cas(self.cxq.state, IDLE, BUSY) then
         return true
      else
         assert(self.cxq.state[0] == DEAD, "illegal state detected")
         self:close()
      end
   end
end

-- Enter the idle state.
function IO:deactivate ()
   assert(sync.cas(self.cxq.state, BUSY, IDLE))
end

local RS = bits({ RS = 5 })
local COMPLETE = 15
function IO:reclaim_txdesc ()

   local cxq = self.cxq
   while band(cxq.txdesc[band(cxq.tx_cand+1, cxq.ring_size-1)].cmd_type_offset_bsz, COMPLETE) == COMPLETE
         and cxq.tx_desc_free < cxq.ring_size - 1 do
      local c = cxq.tx_cand
      packet.free(cxq.txqueue[c])
      cxq.txqueue[c] = nil
      cxq.tx_cand = band(cxq.tx_cand+1, cxq.ring_size-1)
      cxq.tx_desc_free = cxq.tx_desc_free + 1
   end
end

local RS_EOP = bits{ EOP = 4, RS = 5, RSV = 6 }
local IL2TAG1 = bits{ IL2TAG1 = 7}
function IO:transmit (li)
   if li == nil then return end

   local cxq = self.cxq
   local RS_EOP_IL2TAG1 = bor(RS_EOP, (cxq.vlan>0 and IL2TAG1) or 0)
   local L2TAG1 = lshift(0ULL+cxq.vlan, 48)
   local SIZE_SHIFT = 34

   self:reclaim_txdesc()
   while not empty(li) and cxq.tx_desc_free > 0 do
      local p = receive(li)
      local size = lshift(0ULL+p.length, SIZE_SHIFT) -- NB: extend to 64 bit before shift
      cxq.txdesc[ cxq.tx_next ].address = tophysical(p.data)
      cxq.txqueue[ cxq.tx_next ] = p
      cxq.txdesc[ cxq.tx_next ].cmd_type_offset_bsz = bor(RS_EOP_IL2TAG1, size, L2TAG1)
      cxq.tx_next = band(cxq.tx_next+1, cxq.ring_size-1)
      cxq.tx_desc_free = cxq.tx_desc_free - 1
   end
   C.full_memory_barrier()
   self.r.tx_tail(band(cxq.tx_next, cxq.ring_size - 1))
end

function IO:receive (lo)
   if lo == nil then return end

   local pkts = 0
   local cxq = self.cxq
   while band(cxq.rxdesc[cxq.rx_tail].write.status_err_type_len, 0x01) == 1 and pkts < engine.pull_npackets do
      local p = cxq.rxqueue[cxq.rx_tail]
      p.length = rshift(cxq.rxdesc[cxq.rx_tail].write.status_err_type_len, 38)
      transmit(lo, p)

      local np = packet.allocate()
      cxq.rxqueue[cxq.rx_tail] = np
      cxq.rxdesc[cxq.rx_tail].read.address = tophysical(np.data)
      cxq.rxdesc[cxq.rx_tail].write.status_err_type_len = 0
      cxq.rx_tail = band(cxq.rx_tail+1, cxq.ring_size-1)
      pkts = pkts + 1
   end
   -- This avoids the queue being full / empty when HEAD=TAIL
   C.full_memory_barrier()
   self.r.rx_tail(band(cxq.rx_tail-1, cxq.ring_size-1))
end

function IO:push ()
   if self:activate() then
      self:transmit(self.input.input)
      self:deactivate()
   end
end

function IO:pull ()
   if self:activate() then
      self:receive(self.output.output)
      self:deactivate()
   end
end

function Intel_avf:mbox_setup()
   local dlen = 4096
   self.mbox = {
      q_len = 16,
      -- q_len * sizeo(mbox_q_t)
      q_byte_len = 16 * ffi.sizeof(mbox_q_t),
      -- FIXME find reference
      q_alignment = 64,
      datalen = dlen,
      txq_buffers = {},
      rxq_buffers = {},
      send_buf = memory.dma_alloc(dlen),
      hwopcodes = {
         SEND_TO_PF     = 0x0801,
         RECV_FROM_PF   = 0x0802,
         SHUTDOWN_QUEUE = 0x0803
      },
      opcodes = {
         VIRTCHNL_OP_UNKNOWN = 0,
         VIRTCHNL_OP_VERSION = 1,
         VIRTCHNL_OP_RESET_VF = 2,
         VIRTCHNL_OP_GET_VF_RESOURCES = 3,
         -- 4/5 unsupported by CentOS 7 PF
         -- VIRTCHNL_OP_CONFIG_TX_QUEUE = 4,
         -- VIRTCHNL_OP_CONFIG_RX_QUEUE = 5,
         VIRTCHNL_OP_CONFIG_VSI_QUEUES = 6,
         VIRTCHNL_OP_CONFIG_IRQ_MAP = 7,
         VIRTCHNL_OP_ENABLE_QUEUES = 8,
         VIRTCHNL_OP_DISABLE_QUEUES = 9,
         VIRTCHNL_OP_ADD_ETH_ADDR = 10,
         -- VIRTCHNL_OP_DEL_ETH_ADDR = 11,
         VIRTCHNL_OP_ADD_VLAN = 12,
         -- VIRTCHNL_OP_DEL_VLAN = 13,
         -- VIRTCHNL_OP_CONFIG_PROMISCUOUS_MODE = 14,
         VIRTCHNL_OP_GET_STATS = 15,
         -- VIRTCHNL_OP_RSVD = 16,
         VIRTCHNL_OP_EVENT = 17,
         -- VIRTCHNL_OP_IWARP = 20,
         -- VIRTCHNL_OP_CONFIG_IWARP_IRQ_MAP = 21,
         -- VIRTCHNL_OP_RELEASE_IWARP_IRQ_MAP = 22,
         VIRTCHNL_OP_CONFIG_RSS_KEY = 23,
         VIRTCHNL_OP_CONFIG_RSS_LUT = 24,
         VIRTCHNL_OP_GET_RSS_HENA_CAPS = 25,
         VIRTCHNL_OP_SET_RSS_HENA = 26
      }
   }
   -- VIRTCHNL_OP_RESET_VF is our default ready-state.
   self.mbox.state = self.mbox.opcodes['VIRTCHNL_OP_RESET_VF']
   self:mbox_setup_rxq()
   self:mbox_setup_txq()
end

function Intel_avf:mbox_sr(opcode, datalen)
   self:mbox_send(opcode, datalen)
   return self:mbox_recv(opcode)
end

function Intel_avf:mbox_send(opcode, datalen, timeout)
   assert(opcode == 'VIRTCHNL_OP_RESET_VF' or
             self.mbox.state == self.mbox.opcodes['VIRTCHNL_OP_RESET_VF'])

   opcode = self.mbox.opcodes[opcode]
   self.mbox.state = opcode

   local idx = self.mbox.next_send_idx
   self.mbox.next_send_idx = ( idx + 1 ) % self.mbox.q_len

   self.mbox.txq[idx].flags0 = 0
   self.mbox.txq[idx].flags1 = 0

   self.mbox.txq[idx].opcode = self.mbox.hwopcodes['SEND_TO_PF']
   if datalen > 512 then
      self.mbox.txq[idx].flags0 =
         bit.bor(self.mbox.txq[idx].flags0, bits({ LARGE_BUFFER = 1 }))
   end
   if datalen > 0 then
      self.mbox.txq[idx].flags1
         = bits({ INDIRECT_BUFFER = 2, BUFFER = 4, NO_INTERRUPTS = 5 })
      self.mbox.txq[idx].data_addr_high = tophysical(self.mbox.send_buf) / 2^32
      self.mbox.txq[idx].data_addr_low = tophysical(self.mbox.send_buf) % 2^32
   else
      self.mbox.txq[idx].flags1 = bits({ NO_INTERRUPTS = 5 })
   end
   self.mbox.txq[idx].datalen = datalen
   self.mbox.txq[idx].cookie_high = opcode

   C.full_memory_barrier()

   self.r.VF_ATQT(self.mbox.next_send_idx)

   lib.waitfor(function()
      assert(not (timeout and timeout()), "timeout")
      return self.r.VF_ATQT() == self.mbox.next_send_idx
   end)
   lib.waitfor(function()
      assert(not (timeout and timeout()), "timeout")
      -- 1 == bits({ DescriptorDone = 0 })
      -- 2 == bits({ Complete = 1 })

      return band(self.mbox.txq[idx].flags0, 1) == 1 and
         band(self.mbox.txq[idx].flags0, 2) == 2
   end)
   -- assert error bit is not set
   assert(band(self.mbox.txq[idx].flags0, 4) == 0)
   assert(self.mbox.txq[idx].return_value == 0)
   return
end

function Intel_avf:mbox_send_buf (t)
   ffi.fill(self.mbox.send_buf, self.mbox.datalen)
   return ffi.cast(t, self.mbox.send_buf)
end

function Intel_avf:mbox_sr_version()
   local tt = self:mbox_send_buf(virtchnl_version_ptr_t)
   tt[0].major = 1;
   tt[0].minor = 1;
   self:mbox_sr('VIRTCHNL_OP_VERSION', ffi.sizeof(virtchnl_version_t))
end

function Intel_avf:mbox_sr_caps()
   -- FIXME use mbox_send_buf
   -- FIXME move type up top
   -- avf_get_vf_resource(struct avf_adapter *adapter)
   -- in
   -- dpdk/drivers/net/avf/avf_vchnl.c
   local supported_caps = bits({
      VIRTCHNL_VF_OFFLOAD_L2 = 0,
      VIRTCHNL_VF_OFFLOAD_VLAN = 16, -- NB: Could leave this bit off and let PF handle VLANs
      VIRTCHNL_VF_OFFLOAD_RX_POLLING = 17,
      VIRTCHNL_VF_OFFLOAD_RSS_PF = 19
   })
   ffi.cast('uint32_t *', self.mbox.send_buf)[0] = supported_caps
   local rcvd = self:mbox_sr('VIRTCHNL_OP_GET_VF_RESOURCES', ffi.sizeof('uint32_t'))

   local tt = ffi.cast(virtchnl_vf_resources_ptr_t, rcvd)[0]

   assert(tt.num_vsis == 1, "Only 1 vsi supported")

   -- pg76
   assert(tt.vsi_type == 6, "vsi_type must be VSI_SRIOV (6)")

   assert(bit.band(tt.vf_offload_flag, supported_caps) == supported_caps,
      "PF driver doesn't support the required capabilities")

   self.vsi_id = tt.vsi_id
   -- FIXME Is this needed?
   self.mac = macaddress:from_bytes(tt.default_mac_addr)
   self.rss_key_size = tt.rss_key_size
   self.rss_lut_size = tt.rss_lut_size
end

function Intel_avf:mbox_recv(opcode, async)
   opcode = self.mbox.opcodes[opcode]
   assert(opcode == self.mbox.state)

   local idx = self.mbox.next_recv_idx

   local function dd () return bit.band(self.mbox.rxq[idx].flags0, 1) == 1 end
   if async and not dd() then return false
   else lib.waitfor(dd) end

   self.mbox.state = self.mbox.opcodes['VIRTCHNL_OP_RESET_VF']

   self.mbox.next_recv_idx = ( idx + 1 ) % self.mbox.q_len

   assert(bit.band(self.mbox.rxq[idx].flags0, bits({ ERR = 2 })) == 0)

   local msg_status = ffi.cast(virtchnl_msg_ptr_t, self.mbox.rxq + idx)[0].status
   assert(msg_status == 0, "failure in PF" .. tonumber(msg_status))
   local opcode = ffi.cast(virtchnl_msg_ptr_t, self.mbox.rxq + idx)[0].opcode

   local bflag = bits({ ExternalBuf = 4 })
   local ptr
   if band(self.mbox.rxq[idx].flags1, bflag) == bflag then
      ptr = ffi.new("uint8_t[?]", self.mbox.rxq[idx].datalen)
      ffi.copy(ptr, self.mbox.rxq_buffers[idx], self.mbox.rxq[idx].datalen)
   end

   self.mbox.rxq[idx].datalen = self.mbox.datalen
   self.mbox.rxq[idx].flags0 = 0
   self.mbox.rxq[idx].flags1 = bits({LARGE_BUFFER = 1, BUFFER=4, NO_INTERRUPTS=5})
   ffi.fill(self.mbox.rxq_buffers[idx], self.mbox.datalen)
   self.mbox.rxq[idx].data_addr_high =
         tophysical(self.mbox.rxq_buffers[idx]) / 2^32
   self.mbox.rxq[idx].data_addr_low =
         tophysical(self.mbox.rxq_buffers[idx]) % 2^32

   C.full_memory_barrier()
   self.r.VF_ARQT( idx )
   if opcode == self.mbox.opcodes['VIRTCHNL_OP_EVENT'] then
      return self:mbox_recv('VIRTCHNL_OP_RESET_VF')
   end
   return ptr
end

function Intel_avf:wait_for_vfgen_rstat(timeout)
   -- Constant names stolen from DPDK drivers/net/avf/base/virtchnl.h
   -- Section 6.1 on page 51
   local mask0 = bits( { VIRTCHNL_VFR_COMPLETED = 1 })
   local mask1 = bits( { VIRTCHNL_VFR_VFACTIVE = 2 })
   lib.waitfor(function ()
         assert(not (timeout and timeout()), "timeout")
         local v = self.r.VFGEN_RSTAT()
         return bit.band(mask0, v) == mask0 or bit.band(mask1, v) == mask1
   end)
end

function Intel_avf:new(conf)
   local self = {
      pciaddress = pci.qualified(conf.pciaddr),
      path = pci.path(conf.pciaddr),
      vlan = conf.vlan,
      r = {},
      ring_buffer_size = conf.ring_buffer_size,
      sync_stats_throttle = lib.throttle(1)
   }
   -- PCI device statistics
   local frame = {
      macaddr   = {counter},
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
      txerrors  = {counter}
   }
   self.stats = shm.create_frame("pci/"..self.pciaddress, frame)

   -- pg79 /* number of descriptors, multiple of 32 */
   assert(self.ring_buffer_size % 32 == 0,
      "ring_buffer_size must be a multiple of 32")

   self = setmetatable(self, { __index = Intel_avf })
   self:supported_hardware()
   self.fd = pci.open_pci_resource_locked(self.pciaddress, 0)
   pci.unbind_device_from_linux(self.pciaddress)
   pci.set_bus_master(self.pciaddress, true)
   self.base = pci.map_pci_memory(self.fd)
   self:load_registers()

   -- wait for the nic to be ready, setup the mailbox and then reset it
   -- that way it doesn't matter what state you where given the card
   lib.waitfor(function ()
      return pcall(function ()
         self:wait_for_vfgen_rstat()
         self:mbox_setup()
         self:reset() -- reset can timeout
      end)
   end)

   -- setup the nic for real
   self:mbox_setup()
   self:mbox_sr_version()
   self:mbox_sr_caps()
   self:mbox_sr_rss(conf.nqueues or 1)
   if #conf.macs > 0  then
      self:mbox_sr_add_mac(conf.macs)
   end
   if self.vlan then
      self:mbox_sr_vlan()
   end

   -- publish device MAC address to SHM
   counter.set(self.stats.macaddr, self.mac.bits)
   
   -- Queue setup
   self.cxqs = {}
   for qno=0, (conf.nqueues or 1) - 1 do
      self.cxqs[#self.cxqs+1] = self:init_cxq(qno)
   end

   self:init_irq()
   self:mbox_sr_irq(conf.nqueues or 1)

   self:mbox_sr_q(self.cxqs)
   self:mbox_sr_enable_q(#self.cxqs)

   for _, cxq in ipairs(self.cxqs) do      
      -- CXQ is now fully initialized & ready for attach.
      assert(sync.cas(cxq.state, INIT, FREE))
   end

   if not conf.nqueues then
      -- If number of queues it not explicitly configured default to
      -- old behavior and configure this app to do I/O on a single queue.
      self.io = IO:new{pciaddr=self.pciaddress, queue=0}
      self.io.input, self.io.output = {}, {}
   end

   return self
end

function Intel_avf:link()
   if self.io then
      self.io.input, self.io.output = self.input, self.output
   end
end

function Intel_avf:push ()
   if self.io then
      self.io:push()
   end
   if self.sync_stats_throttle() then
      self:sync_stats()
   end
end

function Intel_avf:pull ()
   if self.io then
      self.io:pull()
   end
   if self.sync_stats_throttle() then
      self:sync_stats()
   end
end

function Intel_avf:sync_stats ()
   if self.mbox.state == self.mbox.opcodes['VIRTCHNL_OP_GET_STATS'] then
      self:mbox_r_stats('async')
   end
   if self.mbox.state == self.mbox.opcodes['VIRTCHNL_OP_RESET_VF'] then
      self:mbox_s_stats()
   end
end

function Intel_avf:flush_stats ()      
   if self.mbox.state == self.mbox.opcodes['VIRTCHNL_OP_GET_STATS'] then
      self:mbox_r_stats()
   end
   self:mbox_s_stats()
   self:mbox_r_stats()
end

function Intel_avf:rxdrop () return counter.read(self.stats.rxdrop) end
function Intel_avf:txdrop () return counter.read(self.stats.txdrop) end

function Intel_avf:reset()
   -- From "Appendix A Virtual Channel Protocol":
   -- VF sends this request to PF with no parameters PF does NOT respond! VF
   -- driver must delay then poll VFGEN_RSTAT register until reset completion
   -- is indicated. The admin queue must be reinitialized after this operation.
   self:mbox_send('VIRTCHNL_OP_RESET_VF', 0, lib.timeout(1))
   -- As per the above we (the VF driver) must "delay". Sadly, the spec does
   -- (as of this time / to my knowledge) not give further clues as to how to
   -- detect that the delay is sufficient. One second turned out to be not
   -- enough in some cases, two seconds has always worked so far.
   C.usleep(2e6)
   self:wait_for_vfgen_rstat(lib.timeout(1))
end

function Intel_avf:stop()
   self:reset()
   pci.set_bus_master(self.pciaddress, false)
   pci.close_pci_resource(self.fd, self.base)
   -- If we have an embedded IO app, stop it.
   if self.io then
      self.io:stop()
   end
   -- Free packets remaining in TX/RX queues.
   for _, cxq in ipairs(self.cxqs) do
      local timeout = lib.timeout(3)
      lib.waitfor(function ()
         assert(not timeout(), "Intel_avf: failed to free queue "..tonumber(cxq.qno))
         return sync.cas(cxq.state, FREE, DEAD) or sync.cas(cxq.state, IDLE, DEAD)
      end)
      self:free_cxq(cxq)
   end
   -- Unlink stats frame.
   shm.unlink("pci/"..self.pciaddress)
end

function Intel_avf:report ()
   self:flush_stats()
   for _, c in ipairs{
      'rxbytes', 'rxpackets', 'rxmcast', 'rxbcast', 'rxdrop', 'rxdrop',
      'txbytes', 'txpackets', 'txmcast', 'txbcast', 'txdrop', 'txerrors'
   } do
      print(("   %-20s %20s"):format(c, lib.comma_value(counter.read(self.stats[c]))))
   end
end

function Intel_avf:init_irq()
   local intv = bit.lshift(20, 5)
   local v = bit.bor(bits({ ENABLE = 0, CLEARPBA = 1, ITR0 = 3, ITR1 = 4}), intv)

   self.r.VFINT_DYN_CTL0(v)
   self.r.VFINT_DYN_CTLN[0](v)
end

function Intel_avf:mbox_sr_irq(nqueues)
   local tt = self:mbox_send_buf(virtchnl_irq_map_info_ptr_t)
   tt.num_vectors = 1
   tt.vsi_id = self.vsi_id
   tt.vector_id = 0
   tt.rxq_map = 2^nqueues-1 -- disable interrupts for all queues
   self:mbox_sr("VIRTCHNL_OP_CONFIG_IRQ_MAP", ffi.sizeof(virtchnl_irq_map_info_t) + 12)
end

function Intel_avf:mbox_sr_add_mac(macs)
   -- pg81
   local tt = self:mbox_send_buf(virtchnl_ether_addr_list_ptr_t)
   tt.vsi = self.vsi_id
   tt.num_elements = #macs
   for i, mac in ipairs(macs) do
      ffi.copy(tt.list[i-1].addr, mac, MAC_ADDR_BYTE_LEN)
   end
   self:mbox_sr('VIRTCHNL_OP_ADD_ETH_ADDR',
                ffi.sizeof(virtchnl_ether_addr_list_t) +
                ffi.sizeof(virtchnl_ether_addr_t) * #macs)
end

function Intel_avf:mbox_sr_rss(nqueues)
   -- Setup HENA
   local tt = self:mbox_send_buf(virtchnl_rss_hena_ptr_t)
   if nqueues == 1 then
      -- pg83
      -- Forcefully disable the NICs RSS features. Contrary to the spec, RSS
      -- capabilites are turned on by default and need to be disabled (as least
      -- under Linux/some NICs.)
      tt.hena = 0
   else
      -- Enable all
      tt.hena = 0xffffffffffffffffULL
   end
   self:mbox_sr('VIRTCHNL_OP_SET_RSS_HENA', ffi.sizeof(virtchnl_rss_hena_t))
   -- Set random RSS key
   local tt = self:mbox_send_buf(virtchnl_rss_key_ptr_t)
   tt.vsi_id = self.vsi_id
   tt.key_len = self.rss_key_size
   ffi.copy(tt.key, lib.random_bytes(self.rss_key_size), self.rss_key_size)
   self:mbox_sr('VIRTCHNL_OP_CONFIG_RSS_KEY',
               ffi.sizeof(virtchnl_rss_key_t) + self.rss_key_size-1)
   -- Setup LUT
   local tt = self:mbox_send_buf(virtchnl_rss_lut_ptr_t)
   tt.vsi_id = self.vsi_id
   tt.lut_entries = self.rss_lut_size
   for i=0, self.rss_lut_size-1 do
      tt.lut[i] = i % nqueues -- fill LUT with configured queues
   end
   self:mbox_sr('VIRTCHNL_OP_CONFIG_RSS_LUT',
                ffi.sizeof(virtchnl_rss_lut_t) + self.rss_lut_size-1)
end

function Intel_avf:mbox_sr_vlan()
   local tt = self:mbox_send_buf(virtchnl_vlan_filter_list_ptr_t)
   tt.vsi_id = self.vsi_id
   tt.num_elements = 1
   tt.vlan_id[0] = self.vlan
   self:mbox_sr('VIRTCHNL_OP_ADD_VLAN',
                ffi.sizeof(virtchnl_vlan_filter_list_t) + ffi.sizeof("uint16_t")*1)
end

function Intel_avf:mbox_s_stats()
   local tt = self:mbox_send_buf(queue_select_ptr_t)
   tt.vsi_id = self.vsi_id
   self:mbox_send('VIRTCHNL_OP_GET_STATS', ffi.sizeof(queue_select_t))
end

function Intel_avf:mbox_r_stats(async)
   local ret = self:mbox_recv('VIRTCHNL_OP_GET_STATS', async)
   if ret == false then return end

   local stats = ffi.cast(eth_stats_ptr_t, ret)
   local set = counter.set

   set(self.stats.rxbytes,   stats.rx_bytes)
   set(self.stats.rxpackets, stats.rx_unicast)
   set(self.stats.rxmcast,   stats.rx_multicast)
   set(self.stats.rxbcast,   stats.rx_broadcast)
   set(self.stats.rxdrop,    stats.rx_discards)
   set(self.stats.rxdrop,    stats.rx_unknown_protocol)

   set(self.stats.txbytes,   stats.tx_bytes)
   set(self.stats.txpackets, stats.tx_unicast)
   set(self.stats.txmcast,   stats.tx_multicast)
   set(self.stats.txbcast,   stats.tx_broadcast)
   set(self.stats.txdrop,    stats.tx_discards)
   set(self.stats.txerrors,  stats.tx_errors)
end

