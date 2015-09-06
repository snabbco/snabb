

local ffi    = require("ffi")
local C      = ffi.C
local memory = require('core.memory')
local packet = require('core.packet')
local band = require('bit').band

local VRing = {}
VRing.__index = VRing

local ringtypes = {}
local function vring_type(n)
   if ringtypes[n] then return ringtypes[n] end

   local rng = ffi.typeof([[
      struct {
         struct {
            uint64_t addr;
            uint32_t len;
            uint16_t flags;
            uint16_t next;
         } desc[$]          __attribute__((aligned(8)));
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
         uint16_t free_head, last_used_idx;
         $ *vring;
         uint64_t vring_physaddr;
         struct packet *packets[$];
      }
   ]], rng, n)
   ffi.metatype(t, VRing)
   ringtypes[n] = t
   return t
end


-- local function allocate_vring(n)
--    local ct = vring_type(n)
--    local ptr, phys, sz = memory.dma_alloc(ffi.sizeof(ct))
--    ffi.fill(ptr, ffi.sizeof(ct))
--    ptr = ffi.cast(ffi.typeof('$ *', ct), ptr)
--    local obj = ptr[0]
--
--    -- arrange descs in a free list
--    for i = 0, n-1 do
--       obj.vring.desc[i].next = i+1
--    end
--    obj.num_free = n;
--
--    return obj, phys, sz
-- end


local function allocate_vring(n)
   local ct = vring_type(n)
   local vr = ffi.new(ct, { num = n })
   local ring_t = ffi.typeof(vr.vring[0])
   local ptr, phys, sz = memory.dma_alloc(ffi.sizeof(vr.vring[0]))
   vr.vring = ffi.cast(ring_t, ptr)
   vr.vring_physaddr = phys

   for i = 0, n-1 do
      vr.vring.desc[i].next = i+1
   end
   vr.num_free = n

   return vr
end


function VRing:can_add()
   return self.num_free > 0
end


function VRing:add(p, len)
   assert(self:can_add(), "trying to add when can't")
   local idx = self.free_head
   local desc = self.vring.desc[idx]
   self.free_head = desc.next
   self.num_free = self.num_free - 1

   self.packets[idx] = p
   desc.addr = p:physical()
   desc.len = len or p.length
   desc.flags = 0       -- TODO: flags
   desc.next = -1

   self.vring.avail.ring[band (self.vring.avail.idx, self.num-1)] = idx
   C.full_memory_barrier()
   self.vring.avail.idx = self.vring.avail.idx + 1
end


function VRing:more_used()
   return self.vring.used.idx ~= self.last_used_idx
end


function VRing:get()
   if not self:more_used() then return nil end

   C.full_memory_barrier()
   local last_used_idx = band(self.last_used_idx, self.num-1)
   local id = self.vring.used.ring[last_used_idx].id
   local p = self.packets[id]
   local desc = self.vring.desc[id]
   assert(p ~= nil and p:physical() == desc.addr and p.length == desc.len)

   self.last_used_idx = self.last_used_idx + 1
   desc.next = self.free_head
   self.free_head = id
   self.num_free = self.num_free + 1

   return p
end


return {
   vring_type = vring_type,
   allocate_vring = allocate_vring,
}
