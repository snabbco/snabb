-- Implements virtio virtq


module(...,package.seeall)

local freelist  = require("core.freelist")
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

-- Support indirect descriptors.
function VirtioVirtq:get_desc()
   local device = self.device
   local ring_desc = self.virtq.desc
   local function indirect_descriptors_negotiated()
      return band(device.features, C.VIRTIO_RING_F_INDIRECT_DESC) == 
                     C.VIRTIO_RING_F_INDIRECT_DESC
   end
   if (indirect_descriptors_negotiated()) then
      return function(id)
         if band(ring_desc[id].flags, C.VIRTIO_DESC_F_INDIRECT) == 0 then
            return ring_desc, id
         else
            local addr = device.map_from_guest(device, ring_desc[id].addr)
            return ffi.cast(vring_desc_ptr_t, addr), 0
         end
      end
   else
      return function(id)
         return ring_desc, id 
      end
   end
end

-- Receive all available packets from the virtual machine.
function VirtioVirtq:get_buffers (kind, ops, header_len)

   local ring = self.virtq.avail.ring
   local device = self.device
   local idx = self.virtq.avail.idx
   local avail, vring_mask = self.avail, self.vring_num-1

   -- Cache function for obtaining ring descriptor.
   local get_desc = self:get_desc()

   while idx ~= avail do

      -- Header
      local v_header_id = ring[band(avail,vring_mask)]
      local desc, id = get_desc(v_header_id)

      local data_desc = desc[id]

      local packet =
         ops.packet_start(device, data_desc.addr, data_desc.len)
      local total_size = header_len

      if not packet then break end

      -- support ANY_LAYOUT
      if header_len < data_desc.len then
         local addr = data_desc.addr + header_len
         local len = data_desc.len - header_len
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

function VirtioVirtq:signal_used()
   if self.virtq.used.idx ~= self.used then
      self.virtq.used.idx = self.used
      if band(self.virtq.avail.flags, C.VRING_F_NO_INTERRUPT) == 0 then
         C.write(self.callfd, eventfd_one, 8)
      end
   end
end
