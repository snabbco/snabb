-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Implements virtio-net device


module(...,package.seeall)

local lib       = require("core.lib")
local link      = require("core.link")
local memory    = require("core.memory")
local packet    = require("core.packet")
local timer     = require("core.timer")
local VirtioVirtq = require("lib.virtio.virtq_device")
local checksum  = require("lib.checksum")
local ffi       = require("ffi")
local C         = ffi.C
local band      = bit.band

require("lib.virtio.virtio.h")
require("lib.virtio.virtio_vring_h")

local char_ptr_t = ffi.typeof("char *")
local virtio_net_hdr_size = ffi.sizeof("struct virtio_net_hdr")
local virtio_net_hdr_type = ffi.typeof("struct virtio_net_hdr *")
local virtio_net_hdr_mrg_rxbuf_size = ffi.sizeof("struct virtio_net_hdr_mrg_rxbuf")
local virtio_net_hdr_mrg_rxbuf_type = ffi.typeof("struct virtio_net_hdr_mrg_rxbuf *")

local invalid_header_id = 0xffff

--[[
   A list of what needs to be implemented in order to fully support
   some of the options.

   - VIRTIO_NET_F_CSUM - enables the SG I/O (resulting in
      multiple chained data buffers in our TX path(self.rxring))
      Required by GSO/TSO/USO. Requires CSUM offload support in the
      HW driver (now intel10g)

   - VIRTIO_NET_F_MRG_RXBUF - enables multiple chained buffers in our RX path
      (self.txring). Also chnages the virtio_net_hdr to virtio_net_hdr_mrg_rxbuf

   - VIRTIO_F_ANY_LAYOUT - the virtio_net_hdr/virtio_net_hdr_mrg_rxbuf is "prepended"
      in the first data buffer instead if provided by a separate descriptor.
      Supported in fairly recent (3.13) Linux kernels

   - VIRTIO_RING_F_INDIRECT_DESC - support indirect buffer descriptors.

   - VIRTIO_NET_F_CTRL_VQ - creates a separate control virt queue

   - VIRTIO_NET_F_MQ - multiple RX/TX queues, usefull for SMP (host/guest).
      Requires VIRTIO_NET_F_CTRL_VQ

--]]
local supported_features = C.VIRTIO_F_ANY_LAYOUT +
                           C.VIRTIO_NET_F_CTRL_VQ +
                           C.VIRTIO_NET_F_MQ +
                           C.VIRTIO_NET_F_CSUM
--[[
   The following offloading flags are also available:
   VIRTIO_NET_F_CSUM
   VIRTIO_NET_F_GUEST_CSUM
   VIRTIO_NET_F_GUEST_TSO4 + VIRTIO_NET_F_GUEST_TSO6 + VIRTIO_NET_F_GUEST_ECN + VIRTIO_NET_F_GUEST_UFO
   VIRTIO_NET_F_HOST_TSO4 + VIRTIO_NET_F_HOST_TSO6 + VIRTIO_NET_F_HOST_ECN + VIRTIO_NET_F_HOST_UFO
]]--

local max_virtq_pairs = 16

VirtioNetDevice = {}

function VirtioNetDevice:new(owner, disable_mrg_rxbuf, disable_indirect_desc)
   assert(owner)
   local o = {
      owner = owner,
      callfd = {},
      kickfd = {},
      virtq = {},
      rx = {},
      tx = {
         p = nil,
         tx_mrg_hdr = ffi.new("struct virtio_net_hdr_mrg_rxbuf*[1]") ,
         data_sent = nil,
         finished = nil
      }
   }

   o = setmetatable(o, {__index = VirtioNetDevice})

   for i = 0, max_virtq_pairs-1 do
      -- TXQ
      o.virtq[2*i] = VirtioVirtq:new()
      o.virtq[2*i].device = o
      -- RXQ
      o.virtq[2*i+1] = VirtioVirtq:new()
      o.virtq[2*i+1].device = o
   end

   self.virtq_pairs = 1
   self.hdr_type = virtio_net_hdr_type
   self.hdr_size = virtio_net_hdr_size

   self.supported_features = supported_features

   if not disable_mrg_rxbuf then
      self.supported_features = self.supported_features
         + C.VIRTIO_NET_F_MRG_RXBUF
   end
   if not disable_indirect_desc then
      self.supported_features = self.supported_features
         + C.VIRTIO_RING_F_INDIRECT_DESC
   end

   return o
end

function VirtioNetDevice:poll_vring_receive ()
   -- RX
   self:receive_packets_from_vm()
   self:rx_signal_used()
end

-- Receive all available packets from the virtual machine.
function VirtioNetDevice:receive_packets_from_vm ()
   local ops = {
      packet_start = self.rx_packet_start,
      buffer_add   = self.rx_buffer_add,
      packet_end   = self.rx_packet_end
   }
   for i = 0, self.virtq_pairs-1 do
      self.ring_id = 2*i+1
      local virtq = self.virtq[self.ring_id]
      virtq:get_buffers('rx', ops, self.hdr_size)
   end
end

function VirtioNetDevice:rx_packet_start(addr, len)
   local rx_p = packet.allocate()

   local rx_hdr = ffi.cast(virtio_net_hdr_type, self:map_from_guest(addr))
   self.rx_hdr_flags = rx_hdr.flags
   self.rx_hdr_csum_start = rx_hdr.csum_start
   self.rx_hdr_csum_offset = rx_hdr.csum_offset

   return rx_p
end

function VirtioNetDevice:rx_buffer_add(rx_p, addr, len)

   local addr = self:map_from_guest(addr)
   local pointer = ffi.cast(char_ptr_t, addr)

   packet.append(rx_p, pointer, len)
   return len
end

function VirtioNetDevice:rx_packet_end(header_id, total_size, rx_p)
   local l = self.owner.output.tx
   if l then
      if band(self.rx_hdr_flags, C.VIO_NET_HDR_F_NEEDS_CSUM) ~= 0 and
         -- Bounds-check the checksum area
         self.rx_hdr_csum_start  <= rx_p.length - 2 and
         self.rx_hdr_csum_offset <= rx_p.length - 2
      then
         checksum.finish_packet(
            rx_p.data + self.rx_hdr_csum_start,
            rx_p.length - self.rx_hdr_csum_start,
            self.rx_hdr_csum_offset)
      end
      link.transmit(l, rx_p)
   else
      debug("droprx", "len", rx_p.length)
      packet.free(rx_p)
   end
   self.virtq[self.ring_id]:put_buffer(header_id, total_size)
end

-- Advance the rx used ring and signal up
function VirtioNetDevice:rx_signal_used()
   for i = 0, self.virtq_pairs-1 do
      self.virtq[2*i+1]:signal_used()
   end
end

function VirtioNetDevice:poll_vring_transmit ()
   -- RX
   self:transmit_packets_to_vm()
   self:tx_signal_used()
end

-- Receive all available packets from the virtual machine.
function VirtioNetDevice:transmit_packets_to_vm ()
   local ops = {}
   if not self.mrg_rxbuf then
      ops = {
         packet_start = self.tx_packet_start,
         buffer_add   = self.tx_buffer_add,
         packet_end   = self.tx_packet_end
      }
   else
      ops = {
         packet_start = self.tx_packet_start_mrg_rxbuf,
         buffer_add   = self.tx_buffer_add_mrg_rxbuf,
         packet_end   = self.tx_packet_end_mrg_rxbuf
      }
   end
   for i = 0, self.virtq_pairs-1 do
      self.ring_id = 2*i
      local virtq = self.virtq[self.ring_id]
      virtq:get_buffers('tx', ops, self.hdr_size)
   end
end

local function validflags(buf, len)
   local valid = checksum.verify_packet(buf, len)

   if valid == true then
      return C.VIO_NET_HDR_F_DATA_VALID
   elseif valid == false then
      return 0
   else
      return C.VIO_NET_HDR_F_NEEDS_CSUM
   end
end




function VirtioNetDevice:tx_packet_start(addr, len)
   local l = self.owner.input.rx
   if link.empty(l) then return nil, nil end
   local tx_p = link.receive(l)

   local tx_hdr = ffi.cast(virtio_net_hdr_type, self:map_from_guest(addr))

   -- TODO: copy the relevnat fields from the packet
   ffi.fill(tx_hdr, virtio_net_hdr_size)
   if band(self.features, C.VIRTIO_NET_F_CSUM) == 0 then
      tx_hdr.flags = 0
   else
      assert(tx_p.length > 14)
      tx_hdr.flags = validflags(tx_p.data+14, tx_p.length-14)
   end

   return tx_p
end

function VirtioNetDevice:tx_buffer_add(tx_p, addr, len)

   local addr = self:map_from_guest(addr)
   local pointer = ffi.cast(char_ptr_t, addr)

   assert(tx_p.length <= len)
   ffi.copy(pointer, tx_p.data, tx_p.length)

   return tx_p.length
end

function VirtioNetDevice:tx_packet_end(header_id, total_size, tx_p)
   packet.free(tx_p)
   self.virtq[self.ring_id]:put_buffer(header_id, total_size)
end

function VirtioNetDevice:tx_packet_start_mrg_rxbuf(addr, len)
   local tx_mrg_hdr = ffi.cast(virtio_net_hdr_mrg_rxbuf_type, self:map_from_guest(addr))
   local l = self.owner.input.rx
   local tx_p = self.tx.p
   ffi.fill(tx_mrg_hdr, virtio_net_hdr_mrg_rxbuf_size)

   -- for the first buffer receive a packet and save its header pointer
   if not tx_p then
      if link.empty(l) then return end
      tx_p = link.receive(l)

      if band(self.features, C.VIRTIO_NET_F_CSUM) == 0 then
         tx_mrg_hdr.hdr.flags = 0
      else
         tx_mrg_hdr.hdr.flags = validflags(tx_p.data+14, tx_p.length-14)
      end

      self.tx.tx_mrg_hdr[0] = tx_mrg_hdr
      self.tx.data_sent = 0
   end

   return tx_p
end

function VirtioNetDevice:tx_buffer_add_mrg_rxbuf(tx_p, addr, len)

   local addr = self:map_from_guest(addr)
   local pointer = ffi.cast(char_ptr_t, addr)

   -- The first buffer is HDR|DATA. All subsequent buffers are DATA only
   -- virtq passes us the pointer to the DATA so we need to adjust
   -- the number fo copied data and the pointer
   local adjust = 0
   if self.tx.tx_mrg_hdr[0].num_buffers ~= 0 then
      adjust = virtio_net_hdr_mrg_rxbuf_size
   end

   -- calculate the amont of data to copy on this pass
   -- take the minimum of the datat left in the packet
   -- and the adjusted buffer len
   local to_copy = math.min(tx_p.length - self.tx.data_sent, len + adjust)

   -- copy the data to the adjusted pointer
   ffi.copy(pointer - adjust, tx_p.data + self.tx.data_sent, to_copy)

   -- update the num_buffers in the first virtio header
   self.tx.tx_mrg_hdr[0].num_buffers = self.tx.tx_mrg_hdr[0].num_buffers + 1
   self.tx.data_sent = self.tx.data_sent + to_copy

   -- have we sent all the data in the packet?
   if self.tx.data_sent == tx_p.length then
      self.tx.finished = true
   end

   -- XXX The "adjust" is needed to counter-balance an adjustment made
   -- in virtq_device. If we don't make this adjustment then we break
   -- chaining together multiple buffers in that we report the size of
   -- each buffer (except for the first) to be 12 bytes more than it
   -- really is. This causes the VM to see an inflated ethernet packet
   -- size which may or may not be noticed by an application.
   --
   -- This formulation is not optimal and it would be nice to make
   -- this code more transparent. -luke
   return to_copy - adjust
end

function VirtioNetDevice:tx_packet_end_mrg_rxbuf(header_id, total_size, tx_p)
   -- free the packet only when all its data is processed
   if self.tx.finished then
      packet.free(tx_p)
      self.tx.p = nil
      self.tx.data_sent = nil
      self.tx.finished = nil
   elseif not self.tx.p then
      self.tx.p = tx_p
   end
   self.virtq[self.ring_id]:put_buffer(header_id, total_size)
end

-- Advance the rx used ring and signal up
function VirtioNetDevice:tx_signal_used()
   for i = 0, self.virtq_pairs-1 do
      self.virtq[2*i]:signal_used()
   end
end

function VirtioNetDevice:map_from_guest (addr)
   local result
   local m = self.mem_table[0]
   -- Check cache first (on-trace fastpath)
   if addr >= m.guest and addr < m.guest + m.size then
      return addr + m.snabb - m.guest
   end
   -- Looping case
   for i = 0, table.getn(self.mem_table) do
      m = self.mem_table[i]
      if addr >= m.guest and addr < m.guest + m.size then
         if i ~= 0 then
            self.mem_table[i] = self.mem_table[0]
            self.mem_table[0] = m
         end
         return addr + m.snabb - m.guest
      end
   end
   error("mapping to host address failed" .. tostring(ffi.cast("void*",addr)))
end

function VirtioNetDevice:map_from_qemu (addr)
   local result = nil
   for i = 0, table.getn(self.mem_table) do
      local m = self.mem_table[i]
      if addr >= m.qemu and addr < m.qemu + m.size then
         result = addr + m.snabb - m.qemu
         break
      end
   end
   if not result then
      error("mapping to host address failed" .. tostring(ffi.cast("void*",addr)))
   end
   return result
end

function VirtioNetDevice:get_features()
   print(string.format("Get features 0x%x\n%s",
                        tonumber(self.supported_features), 
                        get_feature_names(self.supported_features)))
   return self.supported_features
end

function VirtioNetDevice:set_features(features)
   print(string.format("Set features 0x%x\n%s", tonumber(features), get_feature_names(features)))
   self.features = features
   if band(self.features, C.VIRTIO_NET_F_MRG_RXBUF) == C.VIRTIO_NET_F_MRG_RXBUF then
      self.hdr_type = virtio_net_hdr_mrg_rxbuf_type
      self.hdr_size = virtio_net_hdr_mrg_rxbuf_size
      self.mrg_rxbuf = true
   else
      self.hdr_type = virtio_net_hdr_type
      self.hdr_size = virtio_net_hdr_size
      self.mrg_rxbuf = false
   end
   if band(self.features, C.VIRTIO_RING_F_INDIRECT_DESC) == C.VIRTIO_RING_F_INDIRECT_DESC then
      for i = 0, max_virtq_pairs-1 do
         -- TXQ
         self.virtq[2*i]:enable_indirect_descriptors()
         -- RXQ
         self.virtq[2*i+1]:enable_indirect_descriptors()
      end
   end
end

function VirtioNetDevice:set_vring_num(idx, num)
   local n = tonumber(num)
   if band(n, n - 1) ~= 0 then
      error("vring_num should be power of 2")
   end

   self.virtq[idx].vring_num = n
   -- update the curent virtq pairs
   self.virtq_pairs = math.max(self.virtq_pairs, math.floor(idx/2)+1)
end

function VirtioNetDevice:set_vring_call(idx, fd)
   self.virtq[idx].callfd = fd
end

function VirtioNetDevice:set_vring_kick(idx, fd)
   self.virtq[idx].kickfd = fd
end

function VirtioNetDevice:set_vring_addr(idx, ring)

   self.virtq[idx].virtq = ring
   self.virtq[idx].avail = tonumber(ring.used.idx)
   self.virtq[idx].used = tonumber(ring.used.idx)
   print(string.format("rxavail = %d rxused = %d", self.virtq[idx].avail, self.virtq[idx].used))
   ring.used.flags = C.VRING_F_NO_NOTIFY
end

function VirtioNetDevice:ready()
   return self.virtq[0].virtq and self.virtq[1].virtq
end

function VirtioNetDevice:set_vring_base(idx, num)
   self.virtq[idx].avail = num
end

function VirtioNetDevice:get_vring_base(idx)
   return self.virtq[idx].avail
end

function VirtioNetDevice:set_mem_table(mem_table)
   self.mem_table = mem_table
end

function VirtioNetDevice:report()
   debug("txavail", self.virtq[0].virtq.avail.idx,
      "txused", self.virtq[0].virtq.used.idx,
      "rxavail", self.virtq[1].virtq.avail.idx,
      "rxused", self.virtq[1].virtq.used.idx)
end

function VirtioNetDevice:rx_buffers()
   return self.vring_transmit_buffers
end

feature_names = {
   [C.VIRTIO_F_NOTIFY_ON_EMPTY]                 = "VIRTIO_F_NOTIFY_ON_EMPTY",
   [C.VIRTIO_RING_F_INDIRECT_DESC]              = "VIRTIO_RING_F_INDIRECT_DESC",
   [C.VIRTIO_RING_F_EVENT_IDX]                  = "VIRTIO_RING_F_EVENT_IDX",

   [C.VIRTIO_F_ANY_LAYOUT]                      = "VIRTIO_F_ANY_LAYOUT",
   [C.VIRTIO_NET_F_CSUM]                        = "VIRTIO_NET_F_CSUM",
   [C.VIRTIO_NET_F_GUEST_CSUM]                  = "VIRTIO_NET_F_GUEST_CSUM",
   [C.VIRTIO_NET_F_GSO]                         = "VIRTIO_NET_F_GSO",
   [C.VIRTIO_NET_F_GUEST_TSO4]                  = "VIRTIO_NET_F_GUEST_TSO4",
   [C.VIRTIO_NET_F_GUEST_TSO6]                  = "VIRTIO_NET_F_GUEST_TSO6",
   [C.VIRTIO_NET_F_GUEST_ECN]                   = "VIRTIO_NET_F_GUEST_ECN",
   [C.VIRTIO_NET_F_GUEST_UFO]                   = "VIRTIO_NET_F_GUEST_UFO",
   [C.VIRTIO_NET_F_HOST_TSO4]                   = "VIRTIO_NET_F_HOST_TSO4",
   [C.VIRTIO_NET_F_HOST_TSO6]                   = "VIRTIO_NET_F_HOST_TSO6",
   [C.VIRTIO_NET_F_HOST_ECN]                    = "VIRTIO_NET_F_HOST_ECN",
   [C.VIRTIO_NET_F_HOST_UFO]                    = "VIRTIO_NET_F_HOST_UFO",
   [C.VIRTIO_NET_F_MRG_RXBUF]                   = "VIRTIO_NET_F_MRG_RXBUF",
   [C.VIRTIO_NET_F_STATUS]                      = "VIRTIO_NET_F_STATUS",
   [C.VIRTIO_NET_F_CTRL_VQ]                     = "VIRTIO_NET_F_CTRL_VQ",
   [C.VIRTIO_NET_F_CTRL_RX]                     = "VIRTIO_NET_F_CTRL_RX",
   [C.VIRTIO_NET_F_CTRL_VLAN]                   = "VIRTIO_NET_F_CTRL_VLAN",
   [C.VIRTIO_NET_F_CTRL_RX_EXTRA]               = "VIRTIO_NET_F_CTRL_RX_EXTRA",
   [C.VIRTIO_NET_F_CTRL_MAC_ADDR]               = "VIRTIO_NET_F_CTRL_MAC_ADDR",
   [C.VIRTIO_NET_F_CTRL_GUEST_OFFLOADS]         = "VIRTIO_NET_F_CTRL_GUEST_OFFLOADS",

   [C.VIRTIO_NET_F_MQ]                          = "VIRTIO_NET_F_MQ"
}

-- Request fresh Just-In-Time compilation of the vring processing code.
-- 
-- This should be called when the expected workload has changed
-- significantly, for example when a virtual machine loads a new
-- device driver or renegotiates features. This will cause LuaJIT to
-- generate fresh machine code for the traffic processing fast-path.
--
-- See background motivation here:
--   https://github.com/LuaJIT/LuaJIT/issues/208#issuecomment-236423732
function VirtioNetDevice:rejit ()
   local mod = "lib.virtio.virtq_device"
   -- Load fresh copies of the virtq module: one for tx, one for rx.
   local txvirtq = package.loaders[1](mod)(mod)
   local rxvirtq = package.loaders[1](mod)(mod)
   local tx_mt = {__index = txvirtq}
   local rx_mt = {__index = rxvirtq}
   for i = 0, max_virtq_pairs-1 do
      setmetatable(self.virtq[2*i],   tx_mt)
      setmetatable(self.virtq[2*i+1], rx_mt)
   end
end

function get_feature_names(bits)
local string = ""
   for mask,name in pairs(feature_names) do
      if (bit.band(bits,mask) == mask) then
         string = string .. " " .. name
      end
   end
   return string
end

function debug (...)
   if _G.developer_debug then print(...) end
end
