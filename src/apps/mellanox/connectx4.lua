-- Device driver for the Mellanox ConnectX-4 Ethernet controller family.
-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- This is a device driver for Mellanox ConnectX-4 and ConnectX-4 LX
-- ethernet cards. This driver is completely stand-alone and does not
-- depend on any other software such as Mellanox OFED library or the
-- Linux mlx5 driver.
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
local band, bor, shl, shr, bswap, bnot =
   bit.band, bit.bor, bit.lshift, bit.rshift, bit.bswap, bit.bnot

local debug_trace   = false     -- Print trace messages
local debug_hexdump = false     -- Print hexdumps (in Linux mlx5 format)

-- Maximum size of a receive queue table.
-- XXX This is hard-coded in the Linux mlx5 driver too. Could
-- alternatively detect from query_hca_cap.
local rqt_max_size = 128

---------------------------------------------------------------
-- ConnectX4 Snabb app.
--
-- Uses the driver routines to implement ConnectX-4 support in
-- the Snabb app network.
---------------------------------------------------------------

ConnectX4 = {}
ConnectX4.__index = ConnectX4

function ConnectX4:new (conf)
   local self = setmetatable({}, self)
   local pciaddress = pci.qualified(conf.pciaddress)

   local sendq_size = conf.sendq_size or 1024
   local recvq_size = conf.recvq_size or 1024

   local mtu = conf.mtu or 9500

   -- Perform a hard reset of the device to bring it into a blank state.
   --
   -- Reset is performed at PCI level instead of via firmware command.
   -- This is intended to be robust to problems like bad firmware states.
   pci.unbind_device_from_linux(pciaddress)
   pci.reset_device(pciaddress)
   pci.set_bus_master(pciaddress, true)

   -- Setup the command channel
   --
   local mmio, fd = pci.map_pci_memory(pciaddress, 0, true)
   local init_seg = InitializationSegment:new(mmio)
   local hca = HCA:new(init_seg)

   init_seg:cmdq_phy_addr(memory.virtual_to_physical(hca.entry))
   if debug_trace then init_seg:dump() end
   while not init_seg:ready() do
      C.usleep(1000)
   end

   -- Boot the card
   --
   hca:enable_hca()
   hca:set_issi(1)
   hca:alloc_pages(hca:query_pages("boot"))
   if debug_trace then self:dump_capabilities(hca) end

   -- Initialize the card
   --
   hca:alloc_pages(hca:query_pages("init"))
   hca:init_hca()
   hca:alloc_pages(hca:query_pages("regular"))

   if debug_trace then self:check_vport() end

   hca:modify_nic_vport_context(mtu, true, true, true)

   -- Create basic objects that we need
   --
   local uar = hca:alloc_uar()
   local eq = hca:create_eq(uar)
   local pd = hca:alloc_protection_domain()
   local tdomain = hca:alloc_transport_domain()
   local rlkey = hca:query_rlkey()

   -- Create send and receive queues & associated objects
   --
   local tis = hca:create_tis(0, tdomain)
   -- List of all receive queues for hashing traffic across
   local rqlist = {}

   for _, queuename in ipairs(conf.queues) do
      
      local send_cq = hca:create_cq(1,    uar, eq.eqn, true)
      local recv_cq = hca:create_cq(recvq_size, uar, eq.eqn, false)

      -- Allocate work queue memory (receive & send contiguous in memory)
      local wq_doorbell = memory.dma_alloc(16)
      local sendq_size = 1024
      local recvq_size = 1024
      local workqueues = memory.dma_alloc(64 * (sendq_size + recvq_size), 4096)
      local rwq = workqueues                   -- receive work queue
      local swq = workqueues + 64 * recvq_size -- send work queue
      
      -- Create the queue objects
      local sqn = hca:create_sq(send_cq, pd, sendq_size, wq_doorbell, swq, uar, tis)
      hca:modify_sq(sqn, 0, 1) -- RESET -> READY
      local rqn = hca:create_rq(recv_cq, pd, recvq_size, wq_doorbell, rwq)
      hca:modify_rq(rqn, 0, 1) -- RESET -> READY

      table.insert(rqlist, rqn)

      -- Create shared memory objects containing all of the
      -- information needed to access the send and receive queues.
      --
      -- Snabb processes will use this information to take ownership
      -- of the queue to send and receive packets.
      local basepath = "/pci/"..pciaddress.."/"..queuename
      local sendpath = basepath.."/send"
      local recvpath = basepath.."/recv"
      local u64 = function (x) return ffi.cast("uint64_t", x) end
      shm.create_frame(sendpath,
                       {lock     = {counter},
                        sqn      = {counter, sqn},
                        wq       = {counter, u64(swq)},
                        wqsize   = {counter, sendq_size},
                        cqn      = {counter, send_cq.cqn},
                        cqe      = {counter, u64(send_cq.cqe)},
                        doorbell = {counter, u64(wq_doorbell)},
                        uar_page = {counter, uar},
                        rlkey    = {counter, rlkey}})
      shm.create_frame(recvpath,
                       {lock     = {counter},
                        rqn      = {counter, rqn},
                        wq       = {counter, u64(rwq)},
                        wqsize   = {counter, recvq_size},
                        cqn      = {counter, recv_cq.cqn},
                        cqe      = {counter, u64(recv_cq.cqe)},
                        doorbell = {counter, u64(wq_doorbell)},
                        uar_page = {counter, uar},
                        rlkey    = {counter, rlkey}})
   end

   --local tir = hca:create_tir_direct(rqlist[1], tdomain)
   local rqt = hca:create_rqt(rqlist)
   local tir = hca:create_tir_indirect(rqt, tdomain)

   -- Setup packet dispatching.
   -- Just a "wildcard" flow group to send RX packets to the receive queue.
   --
   local rx_flow_table_id = hca:create_root_flow_table(NIC_RX)
   local flow_group_id = hca:create_flow_group_wildcard(rx_flow_table_id, NIC_RX, 0, 0)
   hca:set_flow_table_entry_wildcard(rx_flow_table_id, NIC_RX, flow_group_id, 0, tir)
   hca:set_flow_table_root(rx_flow_table_id, NIC_RX)

   function self:stop ()
      pci.set_bus_master(pciaddress, false)
      pci.reset_device(pciaddress)
      pci.close_pci_resource(fd, mmio)
      mmio, fd = nil
   end

   -- Save "instance variable" values.
   self.hca = hca

   return self
end

function ConnectX4:dump_capabilities (hca)
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

function ConnectX4:check_vport ()
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

function ConnectX4:print_vport_counter ()
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
      :input("opcode", 0x00, 31, 16, 0x103)
      :input("opmod",  0x04, 15, 0, mode)
      :execute()
end

---------------------------------------------------------------
-- Event queues
---------------------------------------------------------------

-- Create an event queue that can be accessed via the given UAR page number.
function HCA:create_eq (uar)
   local numpages = 1
   local log_eq_size = 7 -- 128 entries
   local ptr, phy = memory.dma_alloc(4096, 4096) -- memory for entries
   self:command("CREATE_EQ", 0x10C + numpages*8, 0x0C)
      :input("opcode",        0x00,        31, 16, 0x301)
      :input("log_eq_size",   0x10 + 0x0C, 28, 24, log_eq_size)
      :input("uar_page",      0x10 + 0x0C, 23,  0, uar)
      :input("log_page_size", 0x10 + 0x18, 28, 24, 2) -- XXX best value? 0 or max?
      :input("event bitmask", 0x10 + 0x5C, 31,  0, bits({PageRequest=0xB})) -- XXX more events?
      :input("pas[0] high",   0x110,       31,  0, ptrbits(phy, 63, 32))
      :input("pas[0] low",    0x114,       31,  0, ptrbits(phy, 31,  0))
      :execute()
   local eqn = self:output(0x08, 7, 0)
   return eq:new(eqn, ptr, 2^log_eq_size)
end

-- Event Queue Entry (EQE)
local eqe_t = ffi.typeof[[
  struct {
    uint16_t event_type;
    uint16_t event_sub_type;
    uint32_t event_data;
    uint16_t pad;
    uint8_t signature;
    uint8_t owner;
  }
 ]]

eq = {}
eq.__index = eq

-- Create event queue object.
function eq:new (eqn, pointer, nentries)
   local ring = ffi.cast(ffi.typeof("$*", eqe_t), pointer)
   for i = 0, nentries-1 do
      ring[i].owner = 1
   end
   return setmetatable({eqn = eqn,
                        ring = ring,
                        index = 0,
                        n = nentries},
      self)
end

-- Poll the queue for events.
function eq:poll()
   print("Polling EQ")
   local eqe = self.ring[self.index]
   while eqe.owner == 0 and eqe.event_type ~= 0xFF do
      self.index = self.index + 1
      eqe = self.ring[self.index % self.n]
      self:event(eqe)
   end
   print("done polling EQ")
end

-- Handle an event.
function eq:event ()
   print(("Got event %s.%s"):format(eqe.event_type, eqe.event_sub_type))
   error("Event handling not yet implemented")
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
   local mac_hex = bit.tohex(mac_hi, 4) .. bit.tohex(mac_lo, 8)
   return { min_wqe_inline_mode = self:output(0x10+0x00, 26, 24),
            mtu = self:output(0x10+0x24, 15, 0),
            promisc_uc  = self:output(0x10+0xf0, 31, 31) == 1,
            promisc_mc  = self:output(0x10+0xf0, 30, 30) == 1,
            promisc_all = self:output(0x10+0xf0, 29, 29) == 1,
            permanent_address = mac_hex }
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

-- Create a TIR with indirect dispatching (hashing)
function HCA:create_tir_indirect (rqt, transport_domain)
   self:command("CREATE_TIR", 0x10C, 0x0C)
      :input("opcode",           0x00,        31, 16, 0x900)
      :input("disp_type",        0x20 + 0x04, 31, 28, 1) -- indirect
      :input("rx_hash_symmetric",0x20 + 0x20, 31, 31, 1) -- hash symmetrically
      :input("indirect_table",   0x20 + 0x20, 23,  0, rqt)
      :input("rx_hash_fn",       0x20 + 0x24, 31, 28, 2) -- toeplitz
      :input("transport_domain", 0x20 + 0x24, 23,  0, transport_domain)
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
   local cqe, cqe_phy = memory.dma_alloc(entries * 64, 4096)
   ffi.fill(cqe, entries * 64, 0xFF)
   self:command("CREATE_CQ", 0x114, 0x0C)
      :input("opcode",        0x00,        31, 16, 0x400)
      :input("cc",            0x10 + 0x00, 20, 20, collapsed and 1 or 0)
      :input("oi",            0x10 + 0x00, 17, 17, collapsed and 1 or 0)
      :input("log_cq_size",   0x10 + 0x0C, 28, 24, log2size(entries))
      :input("uar_page",      0x10 + 0x0C, 23,  0, uar_page)
      :input("c_eqn",         0x10 + 0x14,  7,  0, eqn)
      :input("log_page_size", 0x10 + 0x18, 28, 24, 4)
      :input("db_addr high",  0x10 + 0x38, 31,  0, ptrbits(doorbell_phy, 63, 32))
      :input("db_addr_low",   0x10 + 0x3C, 31,  0, ptrbits(doorbell_phy, 31, 0))
      :input("pas[0] high",   0x110,       31,  0, ptrbits(cqe_phy, 63, 32))
      :input("pas[0] low",    0x114,       31,  0, ptrbits(cqe_phy, 31, 0))
      :execute()
   local cqn = self:output(0x08, 23, 0)
   return { cqn = cqn, doorbell = doorbell, cqe = cqe }
end

-- Create a receive queue and return a receive queue object.
-- Return the receive queue number and a pointer to the WQEs.
function HCA:create_rq (cq, pd, size, doorbell, rwq)
   local log_wq_size = log2size(size)
   local db_phy = memory.virtual_to_physical(doorbell)
   local rwq_phy = memory.virtual_to_physical(rwq)
   self:command("CREATE_RQ", 0x20 + 0x30 + 0xC4, 0x0C)
      :input("opcode",        0x00, 31, 16, 0x908)
      :input("rlkey",         0x20 + 0x00, 31, 31, 1)
      :input("vlan_strip_disable", 0x20 + 0x00, 28, 28, 1)
      :input("cqn",           0x20 + 0x08, 23, 0, cq.cqn)
      :input("wq_type",       0x20 + 0x30 + 0x00, 31, 28, 1) -- cyclic
      :input("pd",            0x20 + 0x30 + 0x08, 23,  0, pd)
      :input("dbr_addr high", 0x20 + 0x30 + 0x10, 31,  0, ptrbits(db_phy, 63, 32))
      :input("dbr_addr low",  0x20 + 0x30 + 0x14, 31,  0, ptrbits(db_phy, 31, 0))
      :input("log_wq_stride", 0x20 + 0x30 + 0x20, 19, 16, 4)
      :input("page_size",     0x20 + 0x30 + 0x20, 12,  8, 4) -- XXX one big page?
      :input("log_wq_size",   0x20 + 0x30 + 0x20,  4 , 0, log_wq_size)
      :input("pas[0] high",   0x20 + 0x30 + 0xC0, 63, 32, ptrbits(rwq_phy, 63, 32))
      :input("pas[0] low",    0x20 + 0x30 + 0xC4, 31,  0, ptrbits(rwq_phy, 31, 0))
      :execute()
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
function HCA:create_sq (cq, pd, size, doorbell, swq, uar, tis)
   local log_wq_size = log2size(size)
   local db_phy = memory.virtual_to_physical(doorbell)
   local swq_phy = memory.virtual_to_physical(swq)
   self:command("CREATE_SQ", 0x20 + 0x30 + 0xC4, 0x0C)
      :input("opcode",         0x00,               31, 16, 0x904)
      :input("rlkey",          0x20 + 0x00,        31, 31, 1)
      :input("fre",            0x20 + 0x00,        29, 29, 1)
      :input("flush_in_error_en",   0x20 + 0x00,   28, 28, 1)
      :input("min_wqe_inline_mode", 0x20 + 0x00,   26, 24, 1)
      :input("cqn",            0x20 + 0x08,        23, 0, cq.cqn)
      :input("tis_lst_sz",     0x20 + 0x20,        31, 16, 1)
      :input("tis",            0x20 + 0x2C,        23, 0, tis)
      :input("wq_type",        0x20 + 0x30 + 0x00, 31, 28, 1) -- cyclic
      :input("pd",             0x20 + 0x30 + 0x08, 23, 0, pd)
      :input("uar_page",       0x20 + 0x30 + 0x0C, 23, 0, uar)
      :input("pas[0] high",    0x20 + 0x30 + 0x10, 31, 0, ptrbits(db_phy, 63, 32))
      :input("pas[0] low",     0x20 + 0x30 + 0x14, 31, 0, ptrbits(db_phy, 31, 0))
      :input("log_wq_stride",  0x20 + 0x30 + 0x20, 19, 16, 6)
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

function IO:new (conf)
   local self = setmetatable({}, self)
   local pciaddress = pci.qualified(conf.pciaddress)
   local mmio, fd = pci.map_pci_memory(pciaddress, 0, false)

   local queue = conf.queue

   local basepath = "/pci/"..pciaddress.."/"..queue
   local sendpath = basepath.."/send"
   local recvpath = basepath.."/recv"
      
   local send = shm.open_frame(sendpath)
   local recv = shm.open_frame(recvpath)

   self.sq = SQ:new(tonumber(counter.read(send.sqn)),
                    counter.read(send.wq),
                    tonumber(counter.read(send.wqsize)),
                    counter.read(send.doorbell),
                    mmio,
                    tonumber(counter.read(send.uar_page)),
                    tonumber(counter.read(send.rlkey)),
                    counter.read(send.cqe))
   self.rq = RQ:new(counter.read(recv.rqn),
                    counter.read(recv.wq),
                    tonumber(counter.read(recv.wqsize)),
                    counter.read(recv.doorbell),
                    tonumber(counter.read(recv.rlkey)),
                    counter.read(recv.cqe))
   return self
end

function IO:push ()
   local l = self.input.input
   if l == nil then return end
   self.sq:transmit(l)
   self.sq:reclaim()
end

function IO:pull ()
   -- Free transmitted packets
   self.sq:reclaim()
   -- Input received packets
   local l = self.output.output
   if l == nil then return end
   self.rq:ring_doorbell()
   self.rq:receive(l)
end

---------------------------------------------------------------
-- Receive queue

-- Work queue entries have irregular shapes and sizes.
-- We operate on them simply as 64-byte chunks.
local wqe_t = ffi.typeof[[
  union {
    uint8_t  u8[64];
    uint32_t u32[0];
    uint64_t u64[0];
  } *
]]

-- CQEs are similar to WQEs.
local cqe_t = wqe_t

local doorbell_t = ffi.typeof[[
  struct {
    uint32_t receive;
    uint32_t send;
  }*
]]

RQ = {}

local rwqe_t = ffi.typeof[[
  struct {
    uint32_t length, lkey, address_high, address_low;
  } *
]]

function RQ:new (rqn, rwq, wqsize, doorbell, rlkey, cq)
   local self = {}
   -- Convert arguments to internal types
   doorbell = ffi.cast(doorbell_t, doorbell)
   rwq = ffi.cast(rwqe_t, rwq)
   cqe = ffi.cast(cqe_t, cq)
   -- Additional state
   local packets = ffi.new("struct packet *[?]", wqsize)
   local next_buffer = 0        -- next position for a buffer in wqe
   local next_completion = 0    -- next completion queue position to process
   local mine = 0               -- cqe ownership bit meaning software-owned

   -- Refill with buffers
   function self:refill ()
      while packets[next_buffer % wqsize] == nil do
         local p = packet.allocate()
         packets[next_buffer % wqsize] = p
         local rwqe = rwq[next_buffer % wqsize]
         local phy = memory.virtual_to_physical(p.data)
         rwqe.length = bswap(packet.max_payload)
         rwqe.lkey = bswap(rlkey)
         rwqe.address_high = bswap(tonumber(shr(phy, 32)))
         rwqe.address_low  = bswap(tonumber(band(phy, 0xFFFFFFFF)))
         next_buffer = (next_buffer + 1) % 65536
      end
   end

   function self:receive (l)
      while not link.full(l) do
         -- Find the next completion entry.
         local c = cqe[next_completion]
         local owner = bit.band(1, c.u8[0x3F])
         if owner ~= mine then
            -- Completion entry is not available yet.
            break
         end
         -- Advance to next completion.
         next_completion = (next_completion + 1) % wqsize -- XXX cqsize
         -- Toggle the ownership value if the CQ wraps around.
         if next_completion == 0 then
            mine = (mine + 1) % 2
         end
         -- Decode the completion entry.
         local opcode = shr(c.u8[0x3F], 4)
         local len = bswap(c.u32[0x2C/4])
         local wqe = shr(bswap(c.u32[0x3C/4]), 16)
         local idx = wqe % wqsize
         if opcode == 0 or opcode == 2 then
            -- Successful transmission.
            assert(packets[idx] ~= nil)
            link.transmit(l, packets[idx])
            packets[idx] = nil
         elseif opcode == 13 or opcode == 14 then
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
            print(("Got error. opcode=%d syndrome=0x%x message=%s"):format(
                  opcode, syndrome, syndromes[syndromes])) -- XXX
            -- Error on transmission.
            assert(packets[idx] ~= nil)
            packet.free(packets[idx])
            packets[idx] = nil
         else
            error(("Unexpected CQE opcode: %d (0x%x)"):format(opcode, opcode))
         end
      end
   end

   function self:ring_doorbell ()
      doorbell[0].receive = bswap(next_buffer)
   end

   return self
end

---------------------------------------------------------------
-- Send queue

SQ = {}

function SQ:new (sqn, swq, wqsize, doorbell, mmio, uar, rlkey, cq)
   local self = {}
   -- Cast pointers to expected types
   mmio = ffi.cast("uint8_t*", mmio)
   swq = ffi.cast(wqe_t, swq)
   doorbell = ffi.cast(doorbell_t, doorbell)
   -- Additional state
   local packets = ffi.new("struct packet *[?]", wqsize)
   local next_packet = 0
   local next_wqeid  = 0
   -- Locate "blue flame" register areas for the UAR page
   local bf_next = ffi.cast("uint64_t*", mmio + (uar * 4096) + 0x800)
   local bf_alt  = ffi.cast("uint64_t*", mmio + (uar * 4096) + 0x900)
   local cqe = ffi.cast(cqe_t, cq)

   -- Transmit packets from the link onto the send queue.
   function self:transmit (l)
      local start_wqeid = next_wqeid
      while not link.empty(l) and packets[next_packet] == nil do
         local p = link.receive(l)
         local wqe = swq[next_packet]
         packets[next_packet] = p
         -- Control segment
         wqe.u32[0] = bswap(shl(next_wqeid, 8) + 0x0A)
         wqe.u32[1] = bswap(shl(sqn, 8) + 4)
         wqe.u32[2] = bswap(shl(2, 2)) -- completion always
         -- Ethernet segment
         local ninline = 16
         wqe.u32[7] = bswap(shl(ninline, 16))
         ffi.copy(wqe.u8 + 0x1E, p.data, ninline)
         -- Send Data Segment (inline data)
         wqe.u32[12] = bswap(p.length - ninline)
         wqe.u32[13] = bswap(rlkey)
         local phy = memory.virtual_to_physical(p.data + ninline)
         wqe.u32[14] = bswap(tonumber(phy) / 2^32)
         wqe.u32[15] = bswap(tonumber(phy) % 2^32)
         -- Advance counters
         next_wqeid = (next_wqeid + 1) % 65536
         next_packet = next_wqeid % wqsize
      end
      -- Ring the doorbell if we enqueued new packets.
      if next_wqeid ~= start_wqeid then
         local current_packet = (next_packet + wqsize-1) % wqsize
         doorbell.send = bswap(next_wqeid)
         bf_next[0] = swq[current_packet].u64[0]
         -- Switch next/alternate blue flame register for next time
         bf_next, bf_alt = bf_alt, bf_next
         
      end
   end

   local next_reclaim = 0
   -- Free packets when their transmission is complete.
   function self:reclaim ()
      local c = cqe[0]
      local opcode = cqe.u8[0x38]
      local wqeid = shr(bswap(cqe.u32[0x3C/4]), 16)
      if opcode == 0x0A then
         while next_reclaim ~= wqeid % wqsize do
            assert(packets[next_reclaim] ~= nil)
            packet.free(packets[next_reclaim])
            packets[next_reclaim] = nil
            next_reclaim = (next_reclaim + 1) % wqsize
         end
      end
   end

   return self
end

NIC_RX = 0 -- Flow table type code for incoming packets
NIC_TX = 1 -- Flow table type code for outgoing packets

-- Create the root flow table.
function HCA:create_root_flow_table (table_type)
   self:command("CREATE_FLOW_TABLE", 0x3C, 0x0C)
      :input("opcode",     0x00,        31, 16, 0x930)
      :input("table_type", 0x10,        31, 24, table_type)
      :input("log_size",   0x18 + 0x00,  7,  0, 4) -- XXX make parameter
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
      :input("opcode",         0x00, 31, 16, 0x933)
      :input("table_type",     0x10, 31, 24, table_type)
      :input("table_id",       0x14, 23,  0, table_id)
      :input("start_ix",       0x1C, 31,  0, start_ix)
      :input("end_ix",         0x24, 31,  0, end_ix) -- (inclusive)
      :input("match_criteria", 0x3C,  7,  0, 0) -- match outer headers
      :execute()
   local group_id = self:output(0x08, 23, 0)
   return group_id
end

-- Set a "wildcard" flow table entry that does not match on any fields.
function HCA:set_flow_table_entry_wildcard (table_id, table_type, group_id, flow_index, tir)
   self:command("SET_FLOW_TABLE_ENTRY", 0x40 + 0x300, 0x0C)
      :input("opcode",       0x00,         31, 16, 0x936)
      :input("opmod",        0x04,         15,  0, 0) -- new entry
      :input("table_type",   0x10,         31, 24, table_type)
      :input("table_id",     0x14,         23,  0, table_id)
      :input("flow_index",   0x20,         31,  0, flow_index)
      :input("group_id",     0x40 + 0x04,  31,  0, group_id)
      :input("action",       0x40 + 0x0C,  15,  0, 4) -- action = FWD_DST
      :input("dest_list_sz", 0x40 + 0x10,  23,  0, 1) -- destination list size
      :input("dest_type",    0x40 + 0x300, 31, 24, 2)
      :input("dest_id",      0x40 + 0x300, 23,  0, tir)
      :execute()
end

---------------------------------------------------------------
-- PHY control access
---------------------------------------------------------------

-- Note: portnumber is always 1 because the ConnectX-4 HCA is managing
-- a single physical port.

PAOS = 0x5006 -- Port Administrative & Operational Status
PPLR = 0x5018 -- Port Physical Loopback Register)

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

function HCA:get_port_status ()
   self:command("ACCESS_REGISTER", 0x10, 0x1C)
      :input("opcode", 0x00, 31, 16, 0x805)
      :input("opmod",  0x04, 15,  0, 1) -- read
      :input("register_id", 0x08, 15,  0, PAOS)
      :input("local_port", 0x10, 23, 16, 1)
      :execute()
   return {admin_status = self:output(0x10, 11, 8),
           oper_status = self:output(0x10, 3, 0)}
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
function HCA:new (init_seg)
   local entry = ffi.cast("uint32_t*", memory.dma_alloc(0x40))
   local inboxes, outboxes = {}, {}
   for i = 0, max_mailboxes-1 do
      -- XXX overpadding.. 0x240 alignment is not accepted?
      inboxes[i]  = ffi.cast("uint32_t*", memory.dma_alloc(0x240, 4096))
      outboxes[i] = ffi.cast("uint32_t*", memory.dma_alloc(0x240, 4096))
   end
   return setmetatable({entry = entry,
                        inboxes = inboxes,
                        outboxes = outboxes,
                        init_seg = init_seg,
                        size = init_seg:log_cmdq_size(),
                        stride = init_seg:log_cmdq_stride()},
      {__index = HCA})
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

function HCA:execute ()
   local last_in_ofs = self.input_size
   local last_out_ofs = self.output_size
   if debug_hexdump then
      local dumpoffset = 0
      print("command INPUT:")
      dumpoffset = hexdump(self.entry, 0, 0x40, dumpoffset)
      local ninboxes  = math.ceil((last_in_ofs + 4 - 16) / data_per_mailbox)
      for i = 0, ninboxes-1 do
         local blocknumber = getint(self.inboxes[i], 0x238, 31, 0)
         local address = memory.virtual_to_physical(self.inboxes[i])
         print("Block "..blocknumber.." @ "..bit.tohex(address, 12)..":")
         dumpoffset = hexdump(self.inboxes[i], 0, ffi.sizeof(cmdq_mailbox_t), dumpoffset)
      end
   end

   assert(self:getbits(0x3C, 0, 0) == 1)
   self.init_seg:ring_doorbell(0) --post command
   
   --poll for command completion
   while self:getbits(0x3C, 0, 0) == 1 do
      if self.init_seg:getbits(0x1010, 31, 24) ~= 0 then
         error("HCA health syndrome: " .. bit.tohex(self.init_seg:getbits(0x1010, 31, 24)))
      end
      C.usleep(10000)
   end

   if debug_hexdump then
      local dumpoffset = 0
      print("command OUTPUT:")
      dumpoffset = hexdump(self.entry, 0, 0x40, dumpoffset)
      local noutboxes = math.ceil((last_out_ofs + 4 - 16) / data_per_mailbox)
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

function selftest ()
   io.stdout:setvbuf'no'

   local pcidev0 = lib.getenv("SNABB_PCI_CONNECTX4_0")
   local pcidev1 = lib.getenv("SNABB_PCI_CONNECTX4_1")
   -- XXX check PCI device type
   if not pcidev0 then
      print("SNABB_PCI_CONNECTX4_0 not set")
      os.exit(engine.test_skipped_code)
   end
   if not pcidev1 then
      print("SNABB_PCI_CONNECTX4_1 not set")
      os.exit(engine.test_skipped_code)
   end

   local nic0 = ConnectX4:new{pciaddress = pcidev0, queues = {'a'}}
   local nic1 = ConnectX4:new{pciaddress = pcidev1, queues = {'b'}}
   local io0 = IO:new({pciaddress = pcidev0, queue = 'a'})
   local io1 = IO:new({pciaddress = pcidev1, queue = 'b'})
   io0.input  = { input = link.new('input0') }
   io0.output = { output = link.new('output0') }
   io1.input  = { input = link.new('input1') }
   io1.output = { output = link.new('output1') }

   print("selftest: waiting for both links up")
   while (nic0.hca:query_vport_state().oper_state ~= 1) or
         (nic1.hca:query_vport_state().oper_state ~= 1) do
      C.usleep(1e6)
   end

   local bursts = 100000
   local each   = 100
   print(("Links up. Sending %s packets."):format(lib.comma_value(each*bursts)))

   for i = 1, bursts do
      for _, app in ipairs({io0, io1}) do
         for i = 1, each do
            local p = packet.allocate()
            ffi.fill(p.data, 16, 0xff)
            p.length = 100
            link.transmit(app.input.input, p)
         end
         app:pull()
         app:push()
      end
   end

   print()
   print("NIC0")
   nic0:print_vport_counter()

   print()
   print("NIC1")
   nic1:print_vport_counter()

   nic0:stop()
   nic1:stop()

   print("selftest: complete")
end

