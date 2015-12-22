-- Application to connect to a virtio-net driver implementation
--
-- Licensed under the Apache 2.0 license
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Copyright (c) 2015 Virtual Open Systems
--

module(..., package.seeall)

local debug = _G.developer_debug

local ffi    = require("ffi")
local C      = ffi.C
local memory = require('core.memory')
local band   = require('bit').band

local VirtioVirtq = {}
VirtioVirtq.__index = VirtioVirtq

-- The Host uses this in used->flags to advise the Guest: don't kick me when you add a buffer.
local VRING_USED_F_NO_NOTIFY = 1
-- The Guest uses this in avail->flags to advise the Host: don't interrupt me when you consume a buffer
local VRING_AVAIL_F_NO_INTERRUPT = 1

-- This marks a buffer as continuing via the next field. 
local VRING_DESC_F_NEXT = 1
-- This marks a buffer as write-only (otherwise read-only).
local VRING_DESC_F_WRITE = 2
-- This means the buffer contains a list of buffer descriptors. 
local VRING_DESC_F_INDIRECT = 4

ffi.cdef([[
struct pk_header {
  uint8_t flags;
  uint8_t gso_type;
  uint16_t hdr_len;
  uint16_t gso_size;
  uint16_t csum_start;
  uint16_t csum_offset;
}  __attribute__((packed));
]])
local pk_header_t = ffi.typeof("struct pk_header")
local pk_header_size = ffi.sizeof(pk_header_t)

ffi.cdef([[
  struct vring_desc { 
    /* Address (guest-physical). */ 
    uint64_t addr; 
    /* Length. */ 
    uint32_t len; 
    /* The flags as indicated above. */ 
    uint16_t flags; 
    /* Next field if flags & NEXT */ 
    uint16_t next;
}  __attribute__((packed));
]])
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
         struct pk_header *headers[$];
         struct vring_desc *desc_tables[$];
      }
   ]], rng, n, n, n)
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

   for i = 0, n-1 do
      local desc = vr.vring.desc[i]
      local len = 2 * ffi.sizeof(vring_desc_t)
      ptr, phys = memory.dma_alloc(len)
      vr.desc_tables[i] = ffi.cast("struct vring_desc *", ptr)
      
      desc.addr = phys
      desc.len = len
      desc.flags = VRING_DESC_F_INDIRECT
      desc.next = i + 1
   end

   for i = 0, n-1 do
      local desc_table = vr.desc_tables[i]
      
      -- Packet header descriptor
      local desc = desc_table[0]
      ptr, phys = memory.dma_alloc(pk_header_size)
      vr.headers[i] = ffi.cast("struct pk_header *", ptr)
      desc.addr = phys
      desc.len = pk_header_size
      desc.flags = VRING_DESC_F_NEXT
      desc.next = 1

      -- Packet data descriptor
      desc = desc_table[1]
      desc.addr = 0
      desc.len = 0
      desc.flags = 0
      desc.next = -1
   end
   vr.num_free = n

   -- Disable the interrupts forever, we don't need them
   vr.vring.avail.flags = VRING_AVAIL_F_NO_INTERRUPT
   return vr
end

function VirtioVirtq:can_add()
   return self.num_free
end

function VirtioVirtq:add(p, len, flags, csum_start, csum_offset)

   local idx = self.free_head
   local desc = self.vring.desc[idx]
   local desc_table = self.desc_tables[idx]
   self.free_head = desc.next
   self.num_free = self.num_free -1
   desc.next = -1

   -- Header
   local header = self.headers[idx]
   header[0].flags = flags
   header[0].csum_start = csum_start
   header[0].csum_offset = csum_offset

   -- Packet
   desc = desc_table[1]
   desc.addr = p:physical()
   desc.len = len
   desc.flags = 0
   desc.next = -1

   self.vring.avail.ring[band(self.last_avail_idx, self.num-1)] = idx
   self.last_avail_idx = self.last_avail_idx + 1
   self.packets[idx] = p
end

function VirtioVirtq:add_empty_header(p, len)
   local idx = self.free_head
   local desc = self.vring.desc[idx]
   local desc_table = self.desc_tables[idx]
   self.free_head = desc.next
   self.num_free = self.num_free -1
   desc.next = -1

   -- Header
   local header = self.headers[idx]
   header[0].flags = 0

   -- Packet
   desc = desc_table[1]
   desc.addr = p:physical()

   desc.len = len
   desc.flags = 0
   desc.next = -1

   self.vring.avail.ring[band(self.last_avail_idx, self.num-1)] = idx
   self.last_avail_idx = self.last_avail_idx + 1
   self.packets[idx] = p
end

function VirtioVirtq:update_avail_idx()
   if self.vring.avail.idx ~= self.last_avail_idx then
      C.full_memory_barrier()
      self.vring.avail.idx = self.last_avail_idx
   end
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

  local p = self.packets[idx]
  if debug then assert(p ~= nil) end
  p.length = used.len - pk_header_size
  if debug then assert(p:physical() == self.desc_tables[idx][1].addr) end

  self.last_used_idx = self.last_used_idx + 1
  desc.next = self.free_head
  self.free_head = idx
  self.num_free = self.num_free + 1

  return p
end

function VirtioVirtq:should_notify()
  -- Notify only if the used ring lacks the "no notify" flag
  return band(self.vring.used.flags, VRING_USED_F_NO_NOTIFY) == 0
end

return {
   allocate_virtq = allocate_virtq,
   pk_header_t = pk_header_t
}
