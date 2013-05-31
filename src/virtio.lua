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
                 txbuffers = buffer_table(), -- descriptor#->buffer back-mapping
                 rxbuffers = buffer_table(),
                 rxfree = descriptor_freelist(), -- free receive descriptors
                 txfree = descriptor_freelist(), -- free transmit descriptors
                 txused  = 0, rxused  = 0,   -- 'used' ring cursors  (0..65535)
                 txavail = 0, rxavail = 0,   -- 'avail' ring cursors (0..65535)
                 txpackets = 0, rxpackets = 0 -- statistics
              }
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

-- Table to remember the latest buffer object used with each descriptor.
function buffer_table ()
   return ffi.new("struct buffer*[?]", vring_size)
end

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

function transmit (dev, buf)
   assert(can_transmit(dev), "transmit overflow")
   -- Initialize a transmit descriptor
   local descriptor_index = freelist_remove(dev.txfree)
   local descriptor = dev.txring.desc[descriptor_index]
   descriptor.addr = ffi.cast(uint64_t, buf.ptr)
   descriptor.len  = buf.size
   descriptor.flags = 0
   descriptor.next = 0
   -- Add the descriptor to the 'available' ring
   dev.txring.avail.ring[dev.txavail % vring_size] = descriptor_index
   dev.txavail = (dev.txavail + 1) % 65536
   -- Setup mapping back from descriptor to buffer
   dev.txbuffers[descriptor_index] = buf
   buffer.ref(buf)
end

function can_transmit (dev)
   return dev.txfree.nfree ~= 0
end

function sync_transmit (dev)
   -- Reclaim used descriptors and release buffers that have been transmitted
   while dev.txused ~= dev.txring.used.idx do
      local descriptor_index = dev.txring.used.ring[dev.txused]
      freelist_add(dev.txfree, descriptor_index)
      buffer.deref(dev.txbuffers[descriptor_index])
      dev.txused = (dev.txused + 1) % 65536
      dev.txpackets = dev.txpackets + 1
   end
   -- Make new descriptors available to hardware
   C.full_memory_barrier()
   dev.txring.avail.idx = dev.txavail
   kick(dev.txring)
end

-- Signal the kernel via the 'kick' eventfd that there is new data.
function kick (ring)
   local value = ffi.new("uint64_t[1]")
   value[0] = 1
   C.write(ring.kickfd, value, 8)
end

--- ### Receive

function add_receive_buffer (dev, buf)
   update_vhost_memory_map(dev)
   assert(can_add_receive_buffer(dev), "receive overflow")
   -- Initialize a receive descriptor
   local descriptor_index = freelist_remove(dev.rxfree)
   local descriptor = dev.rxring.desc[descriptor_index]
   descriptor.addr  = ffi.cast(uint64_t, buf.ptr)
   descriptor.len   = buf.maxsize
   descriptor.flags = C.VIRTIO_DESC_F_WRITE -- device should write
   descriptor.next  = 0
   -- Add the descriptor to the 'available' ring
   dev.rxring.avail.ring[dev.rxavail % vring_size] = descriptor_index
   dev.rxavail = (dev.rxavail + 1) % 65536
   -- Setup mapping back from descriptor to buffer
   dev.rxbuffers[descriptor_index] = buf
   buffer.ref(buf)
end

function can_add_receive_buffer (dev)
   return dev.rxfree.nfree ~= 0
end

function receive (dev)
   assert(can_receive(), "unable to receive")
   -- Get descriptor
   local descriptor_index = dev.rxring.used.ring[dev.rxused]
   local descriptor = dev.rxring.desc[descriptor_index]
   local buf = dev.rxbuffers[descriptor_index]
   dev.rxused = (dev.rxused + 1) % 65536
   dev.rxpackets = dev.rxpackets + 1
   -- Update and return buffer
   buf.size = descriptor.size
   buffer.deref(buf)
   return buf
end

function can_receive (dev)
--   print("rxused", dev.rxring.used.idx, dev.rxused)
   return dev.rxused ~= dev.rxring.used.idx
end

function sync_receive (dev)
   C.full_memory_barrier()
   dev.rxring.avail.idx = dev.rxavail
   kick(dev.rxring)
end

--- ### DMA memory map update

-- Make all of our DMA memory usable as vhost packet buffers.
function update_vhost_memory_map (dev)
   assert(C.vhost_set_memory(dev.vhost, memory_regions()) == 0, "vhost memory")
end

-- Construct a vhost memory map for the kernel. The memory map
-- includes all of our currently allocated DMA buffers and reuses
-- the address space of this process. This means that we can use
-- ordinary pointer addresses to DMA buffers in our vring
-- descriptors.
function memory_regions ()
   local vhost_memory = ffi.new("struct vhost_memory")
   local chunks = memory.chunks
   vhost_memory.nregions = #chunks
   vhost_memory.padding = 0
   local vhost_index = 0
   for _,chunk in ipairs(chunks) do
      local r = vhost_memory.regions + vhost_index
      r.guest_phys_addr = ffi.cast("uint64_t", chunk.pointer)
      r.userspace_addr  = ffi.cast("uint64_t", chunk.pointer)
      r.memory_size = chunk.size
      r.flags_padding = 0
      vhost_index = vhost_index + 1
   end
   return vhost_memory
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
   options.program = port.Port.echo
   options.secs = 1
   port.selftest(options)
   print("rx.availidx", dev.rxring.avail.idx)
   print("tx.availidx", dev.txring.avail.idx)
   print("rx.usedidx", dev.rxring.used.idx)
   print("tx.usedidx", dev.txring.used.idx)
   print_stats(dev)
end

function print_stats (dev)
   print("packets transmitted: " .. lib.comma_value(dev.txpackets))
   print("packets received:    " .. lib.comma_value(dev.rxpackets))
end

