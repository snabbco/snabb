-- Implements virtio-net device


module(...,package.seeall)

local buffer    = require("core.buffer")
local freelist  = require("core.freelist")
local lib       = require("core.lib")
local link      = require("core.link")
local memory    = require("core.memory")
local packet    = require("core.packet")
local timer     = require("core.timer")
local tlb       = require("lib.tlb")
local ffi       = require("ffi")
local C         = ffi.C
local band = bit.band


require("lib.virtio.virtio.h")
require("lib.virtio.virtio_vring_h")

local char_ptr_t = ffi.typeof("char *")
local virtio_net_hdr_size = ffi.sizeof("struct virtio_net_hdr")
local packet_info_size = ffi.sizeof("struct packet_info")
local buffer_t = ffi.typeof("struct buffer")

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

function VirtioNetDevice:poll_vring_receive ()
   -- RX
   self:receive_packets_from_vm()
   self:rx_signal_used()
end

function VirtioNetDevice:poll_vring_transmit ()
   -- TX
   self:get_transmit_buffers_from_vm()
   self:transmit_packets_to_vm()
end

-- Receive all available packets from the virtual machine.
function VirtioNetDevice:receive_packets_from_vm ()

   local rxavail = self.rxavail
   local idx = self.rxring.avail.idx

   while idx ~= rxavail do
      if idx == 0 then idx = 65535 else idx = idx - 1 end
      local p = packet.allocate()
      -- Header
      local header_id = self.rxring.avail.ring[band(idx, self.rx_vring_num-1)]
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
         local b = freelist.remove(self.buffer_recs) or lib.malloc(buffer_t)

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

      self.rxavail = band(self.rxavail + 1, 65535)

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
   local txavail = self.txavail
   local idx = self.txring.avail.idx

   while idx ~= txavail do
      if idx == 0 then idx = 65535 else idx = idx - 1 end
      -- Header
      local header_id = self.txring.avail.ring[band(idx, self.tx_vring_num-1)]
      local header_desc  = self.txring.desc[header_id]
      local header_pointer = ffi.cast(char_ptr_t,self:map_from_guest(header_desc.addr))
      --assert(header_desc.len == virtio_net_hdr_size)
      local total_size = virtio_net_hdr_size
      local data_desc = header_desc
      --assert(bit.band(header_desc.flags, C.VIRTIO_DESC_F_NEXT) ~= 0)

      -- Data buffer
      data_desc  = self.txring.desc[data_desc.next]
      local b = freelist.remove(self.buffer_recs) or lib.malloc(buffer_t)

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

      self.txavail = band(self.txavail + 1, 65535)
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
      local b
      should_continue, b = self:vm_buffer(iovec)

      -- fill in the virtio header
      do local virtio_hdr = b.origin.info.virtio.header_pointer
	 ffi.copy(virtio_hdr, p.info, packet_info_size)
      end

      do local used = self.txring.used.ring[band(self.txused, self.tx_vring_num-1)]
	 local v = b.origin.info.virtio
	 --assert(v.header_id ~= invalid_header_id)
	 used.id = v.header_id
	 used.len = virtio_net_hdr_size + iovec.length
      end

      packet.deref(p)

      self.txused = band(self.txused + 1, 65535)
   end

   if not should_continue then
      -- not enough buffers detected, verify once again
      self.not_enough_vm_bufers = not self:more_vm_buffers()
   end

   if self.txring.used.idx ~= self.txused then
      self.txring.used.idx = self.txused
      if bit.band(self.txring.avail.flags, C.VRING_F_NO_INTERRUPT) == 0 then
         C.write(self.callfd[0], eventfd_one, 8)
      end
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
         local used = self.rxring.used.ring[band(self.rxused, self.rx_vring_num-1)]
         used.id = b.origin.info.virtio.header_id
         used.len = b.origin.info.virtio.total_size

         self.rxused = band(self.rxused + 1, 65535)
      end
   end
end

-- Advance the rx used ring and signal up
function VirtioNetDevice:rx_signal_used()
   if self.rxring.used.idx ~= self.rxused then
      self.rxring.used.idx = self.rxused
      if bit.band(self.rxring.avail.flags, C.VRING_F_NO_INTERRUPT) == 0 then
         C.write(self.callfd[1], eventfd_one, 8)
      end
   end
end

local pagebits = memory.huge_page_bits

-- Cache of the latest referenced physical page.
local last_virt_page = false
local last_virt_offset = false
function VirtioNetDevice:translate_physical_addr (addr)
   local page = bit.rshift(addr, pagebits)
   if page == last_virt_page then
      return addr + last_virt_offset
   end
   local phys = memory.virtual_to_physical(addr)
   last_virt_page = page
   last_virt_offset = phys - addr
   return phys
end

local last_guest_page = false
local last_guest_offset = false
function VirtioNetDevice:map_from_guest (addr)
   local page = bit.rshift(addr, pagebits)
   if page == last_guest_page then return addr + last_guest_offset end
   local result
   for i = 0, table.getn(self.mem_table) do
      local m = self.mem_table[i]
      if addr >= m.guest and addr < m.guest + m.size then
         if i ~= 0 then
            self.mem_table[i] = self.mem_table[0]
            self.mem_table[0] = m
         end
         result = addr + m.snabb - m.guest
         last_guest_page = page
         last_guest_offset = m.snabb - m.guest
         break
      end
   end
   if not result then
      error("mapping to host address failed" .. tostring(ffi.cast("void*",addr)))
   end
   return result
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
   print(string.format("Get features 0x%x\n%s", tonumber(supported_features), get_feature_names(supported_features)))
   return supported_features
end

function VirtioNetDevice:set_features(features)
   print(string.format("Set features 0x%x\n%s", tonumber(features), get_feature_names(features)))
end

function VirtioNetDevice:set_vring_num(idx, num)
   local n = tonumber(num)
   if band(n, n - 1) ~= 0 then
      error("vring_num should be power of 2")
   end

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
      self.txused = tonumber(ring.used.idx)
      -- reconnect
      self.txavail = tonumber(ring.used.idx)
      print(string.format("txavail = %d txused = %d", self.txavail, self.txused))
   else
      self.rxring = ring
      self.rxused = tonumber(ring.used.idx)
      -- reconnect
      self.rxavail = tonumber(ring.used.idx)
      print(string.format("rxavail = %d rxused = %d", self.rxavail, self.rxused))
   end
   ring.used.flags = C.VRING_F_NO_NOTIFY
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
   print(...)
end
