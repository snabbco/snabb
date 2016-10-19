-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Application to connect to a virtio-net driver implementation
--
-- Copyright (c) 2015 Virtual Open Systems
--

module(..., package.seeall)

local debug = _G.developer_debug

local ffi    = require("ffi")
local C      = ffi.C
local memory = require('core.memory')
local packet = require('core.packet')
local band   = require('bit').band
require("lib.virtio.virtio.h")
require("lib.virtio.virtio_vring.h")

local physical = memory.virtual_to_physical

local VirtioVirtq = {}
VirtioVirtq.__index = VirtioVirtq

local VRING_F_NO_INTERRUPT = C.VRING_F_NO_INTERRUPT
local VRING_F_NO_NOTIFY = C.VRING_F_NO_NOTIFY

local pk_header_t = ffi.typeof("struct virtio_net_hdr")
local pk_header_size = ffi.sizeof(pk_header_t)
local vring_desc_t = ffi.typeof("struct vring_desc")

local ringtypes = {}
local function vring_type(n)
   if ringtypes[n] then return ringtypes[n] end

   local rng = ffi.typeof([[
      struct {
         struct vring_desc desc[$] __attribute__((aligned(8)));
         struct {
            uint16_t flags;
            uint16_t idx;
            uint16_t ring[$];
         } avail            __attribute__((aligned(8)));
         struct {
            uint16_t flags;
            uint16_t idx;
            struct {
               uint32_t id;
               uint32_t len;
            } ring[$];
         } used             __attribute__((aligned(4096)));
      }
   ]], n, n, n)
   local t = ffi.typeof([[
      struct {
         int num, num_free;
         uint16_t free_head, last_avail_idx, last_used_idx;
         $ *vring;
         uint64_t vring_physaddr;
         struct packet *packets[$];
      }
   ]], rng, n)
   ffi.metatype(t, VirtioVirtq)
   ringtypes[n] = t
   return t
end

local function allocate_virtq(n)
   local ct = vring_type(n)
   local vr = ffi.new(ct, { num = n })
   local ring_t = ffi.typeof(vr.vring[0])
   local ptr, phys = memory.dma_alloc(ffi.sizeof(vr.vring[0]))
   vr.vring = ffi.cast(ring_t, ptr)
   vr.vring_physaddr = phys
   -- Initialize free list.
   vr.free_head = -1
   vr.num_free = 0
   for i = n-1, 0, -1 do
      vr.vring.desc[i].next = vr.free_head
      vr.free_head = i
      vr.num_free = vr.num_free + 1
   end
   -- Disable the interrupts forever, we don't need them
   vr.vring.avail.flags = VRING_F_NO_INTERRUPT
   return vr
end

function VirtioVirtq:can_add()
   return self.num_free
end

function VirtioVirtq:add(p, len, flags, csum_start, csum_offset)
   local idx = self.free_head
   local desc = self.vring.desc[idx]
   self.free_head = desc.next
   self.num_free = self.num_free -1
   desc.next = -1

   p = packet.shiftright(p, pk_header_size)
   local header = ffi.cast("struct virtio_net_hdr *", p.data)
   header.flags = flags
   header.gso_type = 0
   header.hdr_len = 0
   header.gso_size = 0
   header.csum_start = csum_start
   header.csum_offset = csum_offset
   desc.addr = physical(p.data)
   desc.len = len + pk_header_size
   desc.flags = 0
   desc.next = -1

   self.vring.avail.ring[band(self.last_avail_idx, self.num-1)] = idx
   self.last_avail_idx = self.last_avail_idx + 1
   self.packets[idx] = p
end

function VirtioVirtq:add_empty_header(p, len)
   self:add(p, len, 0, 0, 0)
end

function VirtioVirtq:update_avail_idx()
   C.full_memory_barrier()
   self.vring.avail.idx = self.last_avail_idx
end

function VirtioVirtq:can_get()
   --C.full_memory_barrier()

   local idx1, idx2 = self.vring.used.idx, self.last_used_idx
   local adjust = 0

   if idx2 > idx1 then adjust = 0x10000 end

   return idx1 - idx2 + adjust
end

function VirtioVirtq:get()
   local last_used_idx = band(self.last_used_idx, self.num-1)
   local used = self.vring.used.ring[last_used_idx]
   local idx = used.id
   local desc = self.vring.desc[idx]

   -- FIXME: we should allow the NEXT flag or something, though with worse perf
   if debug then assert(desc.flags == 0) end
   local p = self.packets[idx]
   self.packets[idx] = nil
   if debug then assert(p ~= nil) end
   if debug then assert(physical(p.data) == desc.addr) end
   p.length = used.len
   p = packet.shiftleft(p, pk_header_size)

   self.last_used_idx = self.last_used_idx + 1
   desc.next = self.free_head
   self.free_head = idx
   self.num_free = self.num_free + 1

   return p
end

function VirtioVirtq:should_notify()
   -- Notify only if the used ring lacks the "no notify" flag
   return band(self.vring.used.flags, VRING_F_NO_NOTIFY) == 0
end

return {
   allocate_virtq = allocate_virtq,
   pk_header_t = pk_header_t
}
