-- Implements virtio virtq


module(...,package.seeall)

local buffer    = require("core.buffer")
local freelist  = require("core.freelist")
local lib       = require("core.lib")
local memory    = require("core.memory")
local packet    = require("core.packet")
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

-- support indirect descriptors
function VirtioVirtq:get_desc(header_id)
   local ring_desc = self.virtq.desc
   local device = self.device
   local desc, id
   -- Indirect desriptors
   if band(ring_desc[header_id].flags, C.VIRTIO_DESC_F_INDIRECT) == 0 then
      desc = ring_desc
      id = header_id
   else
      local addr = device.map_from_guest(device,ring_desc[header_id].addr)
      desc = ffi.cast(vring_desc_ptr_t, addr)
      id = 0
   end

   return desc, id
end

-- Receive all available packets from the virtual machine.
function VirtioVirtq:get_buffers (kind, ops)

   local ring = self.virtq.avail.ring
   local device = self.device
   local idx = self.virtq.avail.idx
   local avail, vring_mask = self.avail, self.vring_num-1

   while idx ~= avail do

      -- Header
      local header_id = ring[band(avail,vring_mask)]
      local desc, id = self:get_desc(header_id)

      local data_desc = desc[id]

      local header_len = ops.packet_start(device, header_id, data_desc.addr, data_desc.len)

      -- support ANY_LAYOUT
      if header_len < data_desc.len then
         ops.buffer_add(device, data_desc.addr + header_len, data_desc.len - header_len)
      end

      -- Data buffer
      while band(data_desc.flags, C.VIRTIO_DESC_F_NEXT) ~= 0 do
         data_desc  = desc[data_desc.next]
         ops.buffer_add(device, data_desc.addr, data_desc.len)
      end

      ops.packet_end(device)

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

function VirtioVirtq:signal_used()
   if self.virtq.used.idx ~= self.used then
      self.virtq.used.idx = self.used
      if band(self.virtq.avail.flags, C.VRING_F_NO_INTERRUPT) == 0 then
         C.write(self.callfd, eventfd_one, 8)
      end
   end
end
