-- virtio.lua -- Linux 'vhost' interface for ethernet I/O towards the kernel.

module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
local memory = require("memory")
local buffer = require("buffer")

require("virtio_vring_h")
require("virtio_vhost_h")
require("virtio_vhost_client_h")
require("tuntap_h")

vring_size = C.VHOST_VRING_SIZE
uint64_t = ffi.typeof("uint64_t")

function new (tapname)
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
              }
   -- Disable interrupts (eventfd "call"). We are polling anyway.
   dev.rxring.avail.flags = C.VRING_F_NO_INTERRUPT
   dev.txring.avail.flags = C.VRING_F_NO_INTERRUPT
   open(dev, tapname)
   setmetatable(dev, {__index = virtio})
   return dev
end

function open (dev, tapname)
   os.execute("modprobe tun; modprobe vhost_net")
   local tapfd = C.open_tap(tapname);
   assert(C.vhost_open(dev.vhost, tapfd, memory_regions()) == 0)
end

--- ### Data structures: buffer table and descriptor freelist

-- Table to remember the latest object used with each descriptor.
function packet_table () return ffi.new("struct packet*[?]", vring_size) end
function buffer_table () return ffi.new("struct buffer*[?]", vring_size) end

function descriptor_freelist ()
   local fl = { nfree = 0, list = ffi.new("uint16_t[?]", vring_size) }
   for i = 1, vring_size do
      freelist_add(fl, vring_size - i)
   end
   return fl
end

function freelist_add (freelist, n)
   freelist.list[freelist.nfree] = n
   freelist.nfree = freelist.nfree + 1
end

function freelist_remove (freelist)
   assert(freelist.nfree > 0, "freelist allocation failure")
   freelist.nfree = freelist.nfree - 1
   return freelist.list[freelist.nfree]
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
   return dev.txfree.nfree >= (p and p.niovecs or C.PACKET_IOVEC_MAX)
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
   while dev.txused ~= dev.txring.used.idx do
      local descriptor_index = dev.txring.used.ring[dev.txused % vring_size].id
      local descriptor = dev.txring.desc[descriptor_index]
      packet.deref(dev.txpackets[descriptor_index])
      while bit.band(descriptor.flags, C.VIRTIO_DESC_F_NEXT) ~= 0 do
         descriptor_index = descriptor.next
         freelist.add(dev.txfree, descriptor_index)
      end
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
   local descriptor_index = freelist_remove(dev.rxfree)
   local descriptor = dev.rxring.desc[descriptor_index]
   descriptor.addr  = ffi.cast(uint64_t, buf.pointer)
   descriptor.len   = buf.size
   descriptor.flags = C.VIRTIO_DESC_F_WRITE -- device should write
   descriptor.next  = 0
   -- Add the descriptor to the 'available' ring
   dev.rxring.avail.ring[dev.rxavail % vring_size] = descriptor_index
   dev.rxavail = (dev.rxavail + 1) % 65536
   -- Setup mapping back from descriptor to buffer
   dev.rxdirty = true
end

function can_add_receive_buffer (dev)
   return dev.rxfree.nfree ~= 0
end

function receive (dev)
   assert(can_receive(dev), "unable to receive")
   -- Get descriptor
   local p = packet.allocate()
   local descriptor_index = dev.rxring.used.ring[dev.rxused % vring_size].id
   repeat
      local descriptor = dev.rxring.desc[descriptor_index]
      packet.add_iovec(p, dev.rxbuffers[descriptor_index], descriptor.len)
      descriptor_index = descriptor.next
   until bit.band(descriptor.flags, C.VIRTIO_DESC_F_NEXT) == 0
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

-- How many chunks were allocated the last time we updated the vhost memory map?
vhost_mapped_chunks = 0

-- Make all of our DMA memory usable as vhost packet buffers.
function update_vhost_memory_map (dev)
   -- Has a new chunk been allocated since last time?
   if #memory.chunks > vhost_mapped_chunks then
      assert(C.vhost_set_memory(dev.vhost, memory_regions()) == 0, "vhost memory")
      vhost_mapped_chunks = #memory.chunks
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

--- ### Testing

-- Selftest procedure to read packets from a tap device and write them back.
function selftest (options)
   options = options or {}
   local dev = options.dev or new("snabb%d")
   local port = require("port")
   print("virtio selftest")
   options = options or {}
   options.devices = {dev}
   options.program = port.Port.spam
   options.secs = 10
   port.selftest(options)
   print("rx.availidx", dev.rxring.avail.idx)
   print("tx.availidx", dev.txring.avail.idx)
   print("rx.usedidx", dev.rxring.used.idx)
   print("tx.usedidx", dev.txring.used.idx)
--   print_stats(dev)
end

function print_stats (dev)
   print("packets transmitted: " .. lib.comma_value(dev.txpackets))
   print("packets received:    " .. lib.comma_value(dev.rxpackets))
end

