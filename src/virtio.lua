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

   local M = {}

   local vio = ffi.new("struct vio")
   local rx_freelist, tx_freelist
   local rxring, txring = vio.vring[0], vio.vring[1]

   local txpackets, rxpackets = 0, 0

   function init ()
      -- XXX do this better!
      os.execute("modprobe tun")
      os.execute("modprobe vhost_net")
      local tapfd = C.open_tap(tapinterface);
      assert(C.vhost_open(vio, tapfd, memory_regions()) == 0)
      -- Initialize freelists
      rx_freelist, tx_freelist = {}, {}
      for i = 0, C.VIO_VRING_SIZE-1 do
         rx_freelist[i+1] = i
         tx_freelist[i+1] = i
      end
   end M.init = init

   function print_vio (vio)
      print("avail[0].idx:" .. tostring(vio.vring[0].avail.idx))
      print(" used[0].idx:" .. tostring(vio.vring[0].used.idx))
      print(" used[0].pktlen: " .. tostring(vio.vring[0].used.ring[0].len))
      print("avail[1].idx:" .. tostring(vio.vring[1].avail.idx))
      print(" used[1].idx:" .. tostring(vio.vring[1].used.idx))
   end

   local next_tx_avail = 0 -- Next available position in the tx avail ring
   local txbuffers = {}

   function transmit (buf)
      local bufferindex = init_transmit_descriptor(buf.ptr, buf.size)
      assert(bufferindex < C.VIO_VRING_SIZE)
      txbuffers[bufferindex] = buf
      txring.avail.ring[next_tx_avail % C.VIO_VRING_SIZE] = bufferindex
      next_tx_avail = (next_tx_avail + 1) % 65536
      buffer.ref(buf)
   end M.transmit = transmit

   function init_transmit_descriptor (address, size)
      local index = get_transmit_buffer()
      assert(index <= C.VIO_VRING_SIZE)
      local d = txring.desc[index]
      d.addr, d.len, d.flags, d.next = tonumber(ffi.cast("uint64_t",address)), size, 0, 0
      return index
   end

   -- Return the index of an available transmit buffer.
   -- Precondition: transmit_ready() tested to return true.
   function get_transmit_buffer ()
      assert(can_transmit())
      return table.remove(tx_freelist)
   end

   local txused = 0
   function can_reclaim_buffer ()
      return txused ~= txring.used.idx
   end M.can_reclaim_buffer = can_reclaim_buffer

   function reclaim_buffer ()
      assert(can_reclaim_buffer())
      local descindex = txused % C.VIO_VRING_SIZE
      local bufferindex = txring.used.ring[descindex].id
      local buf = txbuffers[bufferindex]
      table.insert(tx_freelist, bufferindex)
      assert(#tx_freelist <= C.VIO_VRING_SIZE)
      buffer.deref(buf)
      txbuffers[bufferindex] = nil
      txused = (txused + 1) % 65536
      txpackets = txpackets + 1
   end M.reclaim_buffer = reclaim_buffer

   function sync_transmit ()
      while can_reclaim_buffer() do reclaim_buffer() end
      C.full_memory_barrier()  txring.avail.idx = next_tx_avail  kick(txring)
   end M.sync_transmit = sync_transmit

   function can_transmit ()
      if tx_freelist[1] == nil then return nil, 'no free descriptors'
      else return true end
   end M.can_transmit = can_transmit

   local next_rx_avail = 0 -- Next available position in the rx avail ring
   local rxbuffers = {}

   function add_receive_buffer (buf)
      local bufferindex = get_rx_buffer()
      assert(bufferindex < C.VIO_VRING_SIZE)
      rxbuffers[bufferindex] = buf
      buffer.ref(buf)
      local desc = rxring.desc[next_rx_avail % C.VIO_VRING_SIZE]
      rxring.avail.ring[next_rx_avail % C.VIO_VRING_SIZE] = bufferindex
      desc.addr, desc.len = ffi.cast("uint64_t", buf.ptr), buf.maxsize
      desc.flags, desc.next = C.VIO_DESC_F_WRITE, 0
      next_rx_avail = (next_rx_avail + 1) % 65536
      -- XXX memory.lua should call this automatically when needed
      update_vhost_memory_map()
   end M.add_receive_buffer = add_receive_buffer

   function get_rx_buffer ()
      assert(can_add_receive_buffer())
      return table.remove(rx_freelist)
   end

   -- Is there a receive descriptor available to store a new buffer in?
   function can_add_receive_buffer ()
      return rx_freelist[1] ~= nil
   end M.can_add_receive_buffer = can_add_receive_buffer

   local rxused = 0
   function receive ()
      assert(can_receive())
      local index = rxring.used.ring[rxused % C.VIO_VRING_SIZE].id
      local buf = rxbuffers[index]
      assert(buf)
      buf.size = rxring.used.ring[rxused % C.VIO_VRING_SIZE].len
      buffer.deref(buf)
      rxbuffers[index] = nil
      rxused = (rxused + 1) % 65536
      table.insert(rx_freelist, index)
      assert(#rx_freelist <= C.VIO_VRING_SIZE)
      rxpackets = rxpackets + 1
      return buf
   end M.receive = receive

   function can_receive ()
      return rxused ~= rxring.used.idx
   end M.can_receive = can_receive

   function sync_receive ()
      C.full_memory_barrier()  rxring.avail.idx = next_rx_avail  kick(rxring)
   end M.sync_receive = sync_receive

   -- Make all of our DMA memory usable as vhost packet buffers.
   function update_vhost_memory_map ()
      assert(C.vhost_set_memory(vio, memory_regions()) == 0, "vhost memory")
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

   function print_stats ()
      print("packets transmitted: " .. lib.comma_value(txpackets))
      print("packets received:    " .. lib.comma_value(rxpackets))
   end

   -- Selftest procedure to read packets from a tap device and write them back.
   function M.selftest (options)
      local port = require("port")
      print("virtio selftest")
      options = options or {}
      options.devices = {M}
      options.program = port.Port.echo
      options.secs = 10
      M.init()
      port.selftest(options)
      print_stats()
   end

   -- Signal the kernel via the 'kick' eventfd that there is new data.
   function kick (ring)
      local value = ffi.new("uint64_t[1]")
      value[0] = 1
      C.write(ring.kickfd, value, 8)
   end

   return M
end

function selftest ()
   print("Testing vhost (virtio) support.")
   local v = virtio.new("vio%d")
   v.init()
   v.selftest()
end

