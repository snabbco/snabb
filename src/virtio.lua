-- virtio.lua -- Linux 'vhost' interface for ethernet I/O towards the kernel.

module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
local memory = require("memory")
local buffer = require("buffer")

require("vhost_client_h")
require("virtio_h")
require("tuntap_h")

function new (tapinterface)
   local vio = ffi.new("struct vio")
   return { vio = vio, rxring = vio.vring[0], txring = vio.vring[1],
            rx_freelist = {}, tx_freelist = {},
            txbuffers = {}, rxbuffers = {},
            txused = 0, rxused = 0,
            next_tx_avail = 0, next_rx_avail = 0
         }
end

function init (dev)
   os.execute("modprobe tun")
   os.execute("modprobe vhost_net")
   local tapfd = C.open_tap(tapinterface);
   assert(C.vhost_open(dev.vio, tapfd, memory_regions(dev)) == 0)
   for i = 0, C.VIO_VRING_SIZE-1 do
      dev.rx_freelist[i+1] = i
      dev.tx_freelist[i+1] = i
   end
end

function transmit (dev, buf)
   local bufferindex = init_transmit_descriptor(dev, buf.ptr, buf.size)
   assert(bufferindex < C.VIO_VRING_SIZE)
   dev.txbuffers[bufferindex] = buf
   dev.txring.avail.ring[next_tx_avail % C.VIO_VRING_SIZE] = bufferindex
   next_tx_avail = (next_tx_avail + 1) % 65536
   buffer.ref(buf)
end

function init_transmit_descriptor (dev, address, size)
   local index = get_transmit_buffer(dev)
   assert(index <= C.VIO_VRING_SIZE)
   local d = dev.txring.desc[index]
   d.addr, d.len, d.flags, d.next = tonumber(ffi.cast("uint64_t",address)), size, 0, 0
   return index
end

-- Return the index of an available transmit buffer.
-- Precondition: transmit_ready() tested to return true.
function get_transmit_buffer (dev)
   assert(can_transmit(dev))
   return table.remove(dev.tx_freelist)
end

function can_reclaim_buffer (dev)
   return dev.txused ~= dev.txring.used.idx
end

function reclaim_buffer (dev)
   assert(can_reclaim_buffer(dev))
   local descindex = dev.txused % C.VIO_VRING_SIZE
   local bufferindex = dev.txring.used.ring[descindex].id
   local buf = dev.txbuffers[bufferindex]
   table.insert(dev.tx_freelist, bufferindex)
   assert(#dev.tx_freelist <= C.VIO_VRING_SIZE)
   buffer.deref(buf)
   dev.txbuffers[bufferindex] = nil
   dev.txused = (dev.txused + 1) % 65536
   dev.txpackets = dev.txpackets + 1
end

function sync_transmit (dev)
   while can_reclaim_buffer(dev) do reclaim_buffer(dev) end
   C.full_memory_barrier()
   dev.txring.avail.idx = dev.next_tx_avail
   kick(dev.txring)
end

function can_transmit (dev)
   if dev.tx_freelist[1] == nil then return nil, 'no free descriptors'
   else return true end
end

function add_receive_buffer (dev, buf)
   local bufferindex = get_rx_buffer(dev)
   assert(bufferindex < C.VIO_VRING_SIZE)
   dev.rxbuffers[bufferindex] = buf
   buffer.ref(buf)
   local desc = dev.rxring.desc[next_rx_avail % C.VIO_VRING_SIZE]
   dev.rxring.avail.ring[next_rx_avail % C.VIO_VRING_SIZE] = bufferindex
   desc.addr, desc.len = ffi.cast("uint64_t", buf.ptr), buf.maxsize
   desc.flags, desc.next = C.VIO_DESC_F_WRITE, 0
   next_rx_avail = (next_rx_avail + 1) % 65536
   -- XXX memory.lua should call this automatically when needed
   update_vhost_memory_map(dev)
end

function get_rx_buffer (dev)
   assert(can_add_receive_buffer(dev))
   return table.remove(dev.rx_freelist)
end

-- Is there a receive descriptor available to store a new buffer in?
function can_add_receive_buffer (dev)
   return dev.rx_freelist[1] ~= nil
end

function receive (dev)
   assert(can_receive(dev))
   local index = dev.rxring.used.ring[rxused % C.VIO_VRING_SIZE].id
   local buf = dev.rxbuffers[index]
   assert(buf)
   buf.size = dev.rxring.used.ring[dev.rxused % C.VIO_VRING_SIZE].len
   buffer.deref(buf)
   dev.rxbuffers[index] = nil
   dev.rxused = (dev.rxused + 1) % 65536
   table.insert(dev.rx_freelist, index)
   assert(#dev.rx_freelist <= C.VIO_VRING_SIZE)
   dev.rxpackets = dev.rxpackets + 1
   return buf
end

function can_receive (dev)
   return dev.rxused ~= dev.rxring.used.idx
end

function sync_receive (dev)
   C.full_memory_barrier()
   dev.rxring.avail.idx = dev.next_rx_avail
   kick(dev.rxring)
end

-- Make all of our DMA memory usable as vhost packet buffers.
function update_vhost_memory_map (dev)
   assert(C.vhost_set_memory(dev.vio, memory_regions()) == 0, "vhost memory")
end

-- Construct a vhost memory map for the kernel. The memory map
-- includes all of our currently allocated DMA buffers and reuses
-- the address space of this process. This means that we can use
-- ordinary pointer addresses to DMA buffers in our vring
-- descriptors.
function memory_regions ()
   local vio_memory = ffi.new("struct vio_memory")
   local chunks = memory.chunks
   vio_memory.nregions = #chunks
   vio_memory.padding = 0
   local vio_index = 0
   for _,chunk in ipairs(chunks) do
      local r = vio_memory.regions + vio_index
      r.guest_phys_addr = ffi.cast("uint64_t", chunk.pointer)
      r.userspace_addr  = ffi.cast("uint64_t", chunk.pointer)
      r.memory_size = chunk.size
      r.flags_padding = 0
      vio_index = vio_index + 1
   end
   return vio_memory
end

function print_stats (dev)
   print("packets transmitted: " .. lib.comma_value(dev.txpackets))
   print("packets received:    " .. lib.comma_value(dev.rxpackets))
end

-- Selftest procedure to read packets from a tap device and write them back.
function selftest (dev)
   dev = dev or new("vio%d")
   local port = require("port")
   print("virtio selftest")
   options = options or {}
   options.devices = {dev}
   options.program = port.Port.echo
   options.secs = 10
   dev.init()
   port.selftest(options)
   print_stats()
end

-- Signal the kernel via the 'kick' eventfd that there is new data.
function kick (ring)
   local value = ffi.new("uint64_t[1]")
   value[0] = 1
   C.write(ring.kickfd, value, 8)
end

