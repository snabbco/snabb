-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Implements virtio virtq


local lib       = require("core.lib")
local memory    = require("core.memory")
local ffi       = require("ffi")
local C         = ffi.C
local band      = bit.band
local rshift    = bit.rshift
require("lib.virtio.virtio.h")
require("lib.virtio.virtio_vring_h")

--[[
--]]

local vring_desc_ptr_t = ffi.typeof("struct vring_desc *")

VirtioVirtq = {}

function VirtioVirtq:new()
   local o = {}
   return setmetatable(o, {__index = VirtioVirtq})
end

function VirtioVirtq:enable_indirect_descriptors ()
   self.get_desc = self.get_desc_indirect
end

function VirtioVirtq:get_desc_indirect (id)
   local device = self.device
   local ring_desc = self.virtq.desc
   if band(ring_desc[id].flags, C.VIRTIO_DESC_F_INDIRECT) == 0 then
      return ring_desc, id
   else
      local addr = device.map_from_guest(device, ring_desc[id].addr)
      return ffi.cast(vring_desc_ptr_t, addr), 0
   end
end

function VirtioVirtq:get_desc_direct (id)
   return self.virtq.desc, id
end

-- Default: don't support indirect descriptors unless
-- enable_indirect_descriptors is called to replace this binding.
VirtioVirtq.get_desc = VirtioVirtq.get_desc_direct

-- Receive all available packets from the virtual machine.
function VirtioVirtq:get_buffers (kind, ops, hdr_len)

   local device = self.device
   local idx = self.virtq.avail.idx
   local avail, vring_mask = self.avail, self.vring_num-1

   while idx ~= avail do

      -- Header
      local v_header_id = self.virtq.avail.ring[band(avail,vring_mask)]
      local desc, id = self:get_desc(v_header_id)

      local data_desc = desc[id]

      local packet =
         ops.packet_start(device, data_desc.addr, data_desc.len)
      local total_size = hdr_len

      if not packet then break end

      -- support ANY_LAYOUT
      if hdr_len < data_desc.len then
         local addr = data_desc.addr + hdr_len
         local len = data_desc.len - hdr_len
         local added_len = ops.buffer_add(device, packet, addr, len)
         total_size = total_size + added_len
      end

      -- Data buffer
      while band(data_desc.flags, C.VIRTIO_DESC_F_NEXT) ~= 0 do
         data_desc  = desc[data_desc.next]
         local added_len = ops.buffer_add(device, packet, data_desc.addr, data_desc.len)
         total_size = total_size + added_len
      end

      ops.packet_end(device, v_header_id, total_size, packet)

      avail = band(avail + 1, 65535)
   end
   self.avail = avail
end

function VirtioVirtq:put_buffer (id, len)
   local used = self.virtq.used.ring[band(self.used, self.vring_num-1)]
   used.id, used.len = id, len

   self.used = band(self.used + 1, 65535)
end

-- Prepared argument for writing a 1 to an eventfd.
local eventfd_one = ffi.new("uint64_t[1]", {1})

function VirtioVirtq:signal_used ()
   if self.virtq.used.idx ~= self.used then
      self.virtq.used.idx = self.used
      C.full_memory_barrier()
      if band(self.virtq.avail.flags, C.VRING_F_NO_INTERRUPT) == 0 then
         C.write(self.callfd, eventfd_one, 8)
      end
   end
end

return VirtioVirtq
