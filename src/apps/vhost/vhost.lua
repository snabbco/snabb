module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local freelist = require("core.freelist")
local memory   = require("core.memory")
local buffer   = require("core.buffer")
local packet   = require("core.packet")
                 require("lib.virtio.virtio_vring_h")
                 require("lib.tuntap.tuntap_h")
                 require("lib.raw.raw_h")
                 require("apps.vhost.vhost_h")
                 require("apps.vhost.vhost_client_h")

vring_size = C.VHOST_VRING_SIZE
uint64_t = ffi.typeof("uint64_t")

function new (name, type)
   local vhost = ffi.new("struct vhost")
   local dev = { vhost = vhost,
                 rxring = vhost.vring[0],    -- vring 0 is for receiving
                 txring = vhost.vring[1],    -- vring 1 is for transmitting
                 txpackets = packet_table(), -- descriptor#->packet back-mapping
                 rxbuffers = buffer_table(), -- descriptor#->buffer back-mapping
                 rxfree = descriptor_freelist(), -- free receive descriptors
                 txfree = descriptor_freelist(), -- free transmit descriptors
                 txused  = 0, rxused  = 0,   -- 'used' ring cursors  (0..65535)
                 txavail = 0, rxavail = 0,   -- 'avail' ring cursors (0..65535)
                 txdirty = false, rxdirty = false, -- we have state to sync?
                 vhost_mapped_chunks = 0 -- # DMA memory regions already mapped
              }
   -- Disable interrupts (eventfd "call"). We are polling anyway.
   dev.rxring.avail.flags = C.VRING_F_NO_INTERRUPT
   dev.txring.avail.flags = C.VRING_F_NO_INTERRUPT
   open(dev, name, type)
   setmetatable(dev, {__index = getfenv()})
   return dev
end

function open (dev, name, type)
   local fd
   if type == "raw" then
      fd = C.open_raw(name)
   else
      os.execute("modprobe tun; modprobe vhost_net")
      fd = C.open_tap(name);
   end
   assert(C.vhost_open(dev.vhost, fd, memory_regions()) == 0)
end

--- ### Data structures: buffer table and descriptor freelist

-- Table to remember the latest object used with each descriptor.
function packet_table () return ffi.new("struct packet*[?]", vring_size) end
function buffer_table () return ffi.new("struct buffer*[?]", vring_size) end

function descriptor_freelist ()
   local fl = freelist.new("uint16_t", vring_size)
   for i = 1, vring_size do
      freelist.add(fl, vring_size - i)
   end
   return fl
end

--- ### Transmit

function transmit (dev, p)
   assert(can_transmit(dev, p), "transmit overflow")
   local prev_descriptor = nil
   for i = 0, p.niovecs-1 do
      local iovec = p.iovecs[i]
      local descriptor_index = freelist.remove(dev.txfree)
      local descriptor = dev.txring.desc[descriptor_index]
      descriptor.addr  = ffi.cast(uint64_t, iovec.buffer.pointer)
      descriptor.len   = iovec.length
      descriptor.flags = 0
      if prev_descriptor == nil then -- first descriptor
         dev.txring.avail.ring[dev.txavail % vring_size] = descriptor_index
         dev.txavail = (dev.txavail + 1) % 65536
         dev.txpackets[descriptor_index] = p
      else
         prev_descriptor.next = descriptor_index
         prev_descriptor.flags = C.VIRTIO_DESC_F_NEXT
      end
      prev_descriptor = descriptor
   end
   packet.ref(p)
   dev.txdirty = true
end

function can_transmit (dev,  p)
   return freelist.nfree(dev.txfree) >= (p and p.niovecs or C.PACKET_IOVEC_MAX)
end

function sync_transmit (dev)
   reclaim_transmitted_packets(dev)
   if dev.txdirty then
      sync_new_packets_for_transmit(dev)
      dev.txdirty = false
   end
end

-- Reclaim used descriptors and unref packets that have been transmitted.
function reclaim_transmitted_packets (dev)
   local used_idx = dev.txring.used.idx
   C.full_memory_barrier()
   while dev.txused ~= used_idx do
      local descriptor_index = dev.txring.used.ring[dev.txused % vring_size].id
      repeat
         packet.deref(dev.txpackets[descriptor_index])
         local descriptor = dev.txring.desc[descriptor_index]
         freelist.add(dev.txfree, descriptor_index)
         descriptor_index = descriptor.next
      until bit.band(descriptor.flags, C.VIRTIO_DESC_F_NEXT) == 0
      dev.txused = (dev.txused + 1) % 65536
   end
end

-- Make the whole transmit queue available for transmission.
function sync_new_packets_for_transmit (dev)
   update_vhost_memory_map(dev)
   -- Make new descriptors available to hardware
   C.full_memory_barrier()
   dev.txring.avail.idx = dev.txavail
   kick(dev.txring)
end

-- Signal the kernel via the 'kick' eventfd that there is new data.
function kick (ring)
   if bit.band(ring.used.flags, C.VRING_F_NO_NOTIFY) == 0 then
      local value = ffi.new("uint64_t[1]")
      value[0] = 1
      C.write(ring.kickfd, value, 8)
   end
end

--- ### Receive

function add_receive_buffer (dev, buf)
   assert(can_add_receive_buffer(dev), "receive overflow")
   -- Initialize a receive descriptor
   local descriptor_index = freelist.remove(dev.rxfree)
   local descriptor = dev.rxring.desc[descriptor_index]
   descriptor.addr  = ffi.cast(uint64_t, buf.pointer)
   descriptor.len   = buf.size
   descriptor.flags = C.VIRTIO_DESC_F_WRITE -- device should write
   descriptor.next  = 0
   local prev_index = dev.rxring.avail.ring[(dev.rxavail + vring_size-1) % vring_size]
   local prev_descriptor = dev.rxring.desc[prev_index % vring_size]
   prev_descriptor.next = descriptor_index
   -- XXX If we uncomment the next line we get invalid id -1 on the used ring.
   -- prev_descriptor.flags = bit.bor(prev_descriptor.flags, C.VIRTIO_DESC_F_NEXT)
   -- Add the descriptor to the 'available' ring
   dev.rxring.avail.ring[dev.rxavail % vring_size] = descriptor_index
   dev.rxavail = (dev.rxavail + 1) % 65536
   -- Setup mapping back from descriptor to buffer
   dev.rxbuffers[descriptor_index] = buf
   dev.rxdirty = true
end

function can_add_receive_buffer (dev)
   return dev.rxfree.nfree ~= 0
end

function receive (dev)
   assert(can_receive(dev), "unable to receive")
   C.full_memory_barrier() -- XXX optimize this away.
   -- Get descriptor
   local p = packet.allocate()
   local used = dev.rxring.used.ring[dev.rxused % vring_size]
   local len = used.len
   local descriptor_index = used.id
   assert(descriptor_index < vring_size, "bad descriptor index")
   -- Loop converting each buffer in the chain into a packet iovec
   repeat
      local descriptor = dev.rxring.desc[descriptor_index]
      local iovec_len = math.min(len, descriptor.len)
      packet.add_iovec(p, dev.rxbuffers[descriptor_index], iovec_len)
      freelist.add(dev.rxfree, descriptor_index)
      descriptor_index = descriptor.next
      len = len - iovec_len
   until len == 0
   dev.rxused = (dev.rxused + 1) % 65536
   return p
end

function can_receive (dev)
   return dev.rxused ~= dev.rxring.used.idx
end

function sync_receive (dev)
   if dev.rxdirty then
      update_vhost_memory_map(dev)
      C.full_memory_barrier()
      dev.rxring.avail.idx = dev.rxavail
      kick(dev.rxring)
      dev.rxdirty = false
   end
end

--- ### DMA memory map update

-- Make all of our DMA memory usable as vhost packet buffers.
function update_vhost_memory_map (dev)
   -- Has a new chunk been allocated since last time?
   if #memory.chunks > dev.vhost_mapped_chunks then
      assert(C.vhost_set_memory(dev.vhost, memory_regions()) == 0, "vhost memory")
      dev.vhost_mapped_chunks = #memory.chunks
   end
end

-- Construct a vhost memory map for the kernel. Use one region of
-- memory from the lowest to highest DMA address, and use addresses in
-- our own virtual address space.
--
-- Note: Vhost supports max 64 regions so it is not practical to
-- advertise each memory chunk individually.
function memory_regions ()
   local mem = ffi.new("struct vhost_memory")
   if not memory.dma_max_addr then
      mem.nregions = 0
   else
      mem.nregions = 1
      mem.regions[0].guest_phys_addr = memory.dma_min_addr
      mem.regions[0].userspace_addr  = memory.dma_min_addr
      mem.regions[0].memory_size = memory.dma_max_addr - memory.dma_min_addr
      mem.regions[0].flags_padding = 0
   end
   return mem
end

