-- Implements virtio-net device


module(...,package.seeall)

local buffer    = require("core.buffer")
local freelist  = require("core.freelist")
local lib       = require("core.lib")
local link      = require("core.link")
local memory    = require("core.memory")
local packet    = require("core.packet")
local timer     = require("core.timer")
local ffi       = require("ffi")
local C         = ffi.C

require("lib.virtio.virtio.h")
require("lib.virtio.virtio_vring_h")

local char_ptr_t = ffi.typeof("char *")
local virtio_net_hdr_size = ffi.sizeof("struct virtio_net_hdr")
local packet_info_size = ffi.sizeof("struct packet_info")

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
      Requires VIRTIO_NET_F_MQ

--]]
local supported_features = 0

VirtioNetDevice = {}

function VirtioNetDevice:new(owner)
   assert(owner)
   local o = {
      owner = owner,
      callfd = {},
      kickfd = {},
      tx_vring_num = 0,
      rx_vring_num = 0,
      -- buffer records that are not currently in use
      buffer_recs = freelist.new("struct buffer *", 32*1024),
      -- buffer records populated with available VM memory
      vring_transmit_buffers = freelist.new("struct buffer *", 32*1024),
   }
   return setmetatable(o, {__index = VirtioNetDevice})
end

function VirtioNetDevice:poll_vring_packets ()
   -- RX
   self:receive_packets_from_vm()
   self:rx_signal_used()
   -- TX
   self:get_transmit_buffers_from_vm()
   self:transmit_packets_to_vm()
end

-- Receive all available packets from the virtual machine.
function VirtioNetDevice:receive_packets_from_vm ()

   while self.rxavail ~= self.rxring.avail.idx do
      local p = packet.allocate()
      -- Header
      local header_id = self.rxring.avail.ring[self.rxavail % self.rx_vring_num]
      local header_desc  = self.rxring.desc[header_id]
      local header_pointer = ffi.cast(char_ptr_t,self:map_from_guest(header_desc.addr))
      --assert(header_desc.len == virtio_net_hdr_size)
      local total_size = virtio_net_hdr_size
      local data_desc = header_desc
      --assert(bit.band(header_desc.flags, C.VIRTIO_DESC_F_NEXT) ~= 0)

      -- Fill in packet header
      ffi.copy(p.info, header_pointer, packet_info_size)

      -- Data buffer
      repeat
         data_desc  = self.rxring.desc[data_desc.next]
         local b = freelist.remove(self.buffer_recs) or lib.malloc("struct buffer")

         local addr = self:map_from_guest(data_desc.addr)
         b.pointer = ffi.cast(char_ptr_t, addr)
         b.physical = self:translate_physical_addr(addr)
         b.size = data_desc.len

         -- The total size will be added to the first buffer virtio info
         total_size = total_size + b.size

         -- Fill buffer origin info
         b.origin.type = C.BUFFER_ORIGIN_VIRTIO
         -- Set invalid header_id for all buffers. The first will contain
         -- the real header_id, set after the loop
         b.origin.info.virtio.header_id = invalid_header_id

         packet.add_iovec(p, b, b.size)
      until bit.band(data_desc.flags, C.VIRTIO_DESC_F_NEXT) == 0

      -- Fill in the first buffer with header info
      local v = p.iovecs[0].buffer.origin.info.virtio
      v.device_id     = self.virtio_device_id
      v.ring_id       = 1 -- rx ring
      v.header_id = header_id
      v.header_pointer = header_pointer
      v.total_size = total_size

      self.rxavail = (self.rxavail + 1) % 65536

      local l = self.owner.output.tx
      if l then
         link.transmit(l, p)
      else
         debug("droprx", "len", p.length, "niovecs", p.niovecs)
         packet.deref(p)
      end
   end
end

-- Populate the `self.vring_transmit_buffers` freelist with buffers from the VM.
function VirtioNetDevice:get_transmit_buffers_from_vm ()
   while self.txavail ~= self.txring.avail.idx do
      -- Header
      local header_id = self.txring.avail.ring[self.txavail % self.tx_vring_num]
      local header_desc  = self.txring.desc[header_id]
      local header_pointer = ffi.cast(char_ptr_t,self:map_from_guest(header_desc.addr))
      --assert(header_desc.len == virtio_net_hdr_size)
      local total_size = virtio_net_hdr_size
      local data_desc = header_desc
      --assert(bit.band(header_desc.flags, C.VIRTIO_DESC_F_NEXT) ~= 0)

      -- Data buffer
      data_desc  = self.txring.desc[data_desc.next]
      local b = freelist.remove(self.buffer_recs) or lib.malloc("struct buffer")

      local addr = self:map_from_guest(data_desc.addr)
      b.pointer = ffi.cast(char_ptr_t, addr)
      b.physical = self:translate_physical_addr(addr)
      b.size = data_desc.len

      -- The total size will be added to the first buffer virtio info
      total_size = total_size + b.size

      -- Fill buffer origin info
      b.origin.type = C.BUFFER_ORIGIN_VIRTIO
      local v = b.origin.info.virtio
      v.device_id     = self.virtio_device_id
      v.ring_id       = 0 -- tx ring
      v.header_id = header_id
      v.header_pointer = header_pointer
      v.total_size = total_size

      freelist.add(self.vring_transmit_buffers, b)

      self.txavail = (self.txavail + 1) % 65536
   end
end

-- Prepared argument for writing a 1 to an eventfd.
local eventfd_one = ffi.new("uint64_t[1]", {1})

function VirtioNetDevice:more_vm_buffers ()
   return freelist.nfree(self.vring_transmit_buffers) > 2
end

-- return the buffer from a iovec, ensuring it originates from the vm
function VirtioNetDevice:vm_buffer (iovec)
   local should_continue = true
   local b = iovec.buffer
   -- check if this is a zero-copy packet
   if b.origin.type ~= C.BUFFER_ORIGIN_VIRTIO then
      -- get buffer from the once supplied by the VM
      local old_b = b
      b = freelist.remove(self.vring_transmit_buffers)
      --assert(iovec.offset + iovec.length <= b.size)

      -- copy the whole buffer data, including offset
      ffi.copy(b.pointer, old_b.pointer, iovec.offset + iovec.length)
      buffer.free(old_b)
      iovec.buffer = b

      if not self:more_vm_buffers() then
         -- no more buffers, stop the loop
         should_continue = false
      end
   end
   return should_continue, b
end

-- Transmit packets from the app input queue to the VM.
function VirtioNetDevice:transmit_packets_to_vm ()
   local l = self.owner.input.rx
   if not l then return end
   local should_continue = not self.not_enough_vm_bufers

   while (not link.empty(l)) and should_continue do
      local p = link.receive(l)

      -- ensure all data is in a single buffer
      if p.niovecs > 1 then
         packet.coalesce(p)
      end

      local iovec = p.iovecs[0]
      should_continue, b = self:vm_buffer(iovec)

      -- fill in the virtio header
      local virtio_hdr = b.origin.info.virtio.header_pointer
      ffi.copy(virtio_hdr, p.info, packet_info_size)

      local used = self.txring.used.ring[self.txused%self.tx_vring_num]
      local v = b.origin.info.virtio
      --assert(v.header_id ~= invalid_header_id)
      used.id = v.header_id
      used.len = virtio_net_hdr_size + iovec.length
      self.txused = (self.txused + 1) % 65536

      packet.deref(p)
   end

   if not should_continue then
      -- not enough buffers detected, verify once again
      self.not_enough_vm_bufers = not self:more_vm_buffers()
   end

   if self.txring.used.idx ~= self.txused then
      self.txring.used.idx = self.txused
      C.write(self.callfd[0], eventfd_one, 8)
   end
end

-- Return a buffer to the virtual machine.
function VirtioNetDevice:return_virtio_buffer (b)
   freelist.add(self.buffer_recs, b)
   if b.origin.info.virtio.ring_id == 1 then -- Receive buffer?

      -- Only do this for the first buffer in the chain.
      -- Distiguish it by the valid header_id
      -- Other buffers in the chain are safe as long as
      -- rx_signal_used() is not called. So be sure to free
      -- all of them at one poll.
      if b.origin.info.virtio.header_id ~= invalid_header_id then
         local used = self.rxring.used.ring[self.rxused % self.rx_vring_num]
         used.id = b.origin.info.virtio.header_id
         used.len = b.origin.info.virtio.total_size

         self.rxused = (self.rxused + 1) % 65536
      end
   end
end

-- Advance the rx used ring and sugnal up
function VirtioNetDevice:rx_signal_used()
   if self.rxring.used.idx ~= self.rxused then
      self.rxring.used.idx = self.rxused
      C.write(self.callfd[1], eventfd_one, 8)
   end
end

function VirtioNetDevice:translate_physical_addr (addr)
   -- Assuming no-IOMMU
   return memory.virtual_to_physical(addr)
end

-- Address space remapping.
function VirtioNetDevice:map_to_guest (addr)
   for i = 0, table.getn(self.mem_table) do
      local m = self.mem_table[i]
      if addr >= m.snabb and addr < m.snabb + m.size then
         return addr + m.guest - m.snabb
      end
   end
   error("mapping to guest address failed")
end

function VirtioNetDevice:map_from_guest (addr)
   for i = 0, table.getn(self.mem_table) do
      local m = self.mem_table[i]
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
   for i = 0, table.getn(self.mem_table) do
      local m = self.mem_table[i]
      if addr >= m.qemu and addr < m.qemu + m.size then
         return addr + m.snabb - m.qemu
      end
   end
   error("mapping to host address failed" .. tostring(ffi.cast("void*",addr)))
end

function VirtioNetDevice:get_features()
   return supported_features
end

function VirtioNetDevice:set_features(features)
   print(string.format("Set features 0x%x", tonumber(features)))
end

function VirtioNetDevice:set_vring_num(idx, num)

   local n = tonumber(num)
   if idx == 0 then
      self.tx_vring_num = n
   else
      self.rx_vring_num = n
   end
end

function VirtioNetDevice:set_vring_call(idx, fd)
   self.callfd[idx] = fd
end

function VirtioNetDevice:set_vring_kick(idx, fd)
   self.kickfd[idx] = fd
end

function VirtioNetDevice:set_vring_addr(idx, ring)
   if idx == 0 then
      self.txring = ring
      self.txused = ring.used.idx
   else
      self.rxring = ring
      self.rxused = ring.used.idx
   end
end

function VirtioNetDevice:ready()
   return self.txring and self.rxring
end

function VirtioNetDevice:set_vring_base(idx, num)
   if idx == 0 then
      self.txavail = num
   else
      self.rxavail = num
   end
end

function VirtioNetDevice:get_vring_base(idx)
   local n = 0
   if idx == 0 then
      n = self.txavail
   else
      n = self.rxavail
   end
   return n
end

function VirtioNetDevice:set_mem_table(mem_table)
   self.mem_table = mem_table
end

function VirtioNetDevice:report()
   debug("txavail", self.txring.avail.idx,
      "txused", self.txring.used.idx,
      "rxavail", self.rxring.avail.idx,
      "rxused", self.rxring.used.idx)
end

function VirtioNetDevice:rx_buffers()
   return self.vring_transmit_buffers
end

function VirtioNetDevice:set_virtio_device_id(virtio_device_id)
   self.virtio_device_id = virtio_device_id
end

function debug (...)
   print(...)
end
