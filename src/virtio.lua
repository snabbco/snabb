-- virtio.lua -- Linux 'vhost' interface for ethernet I/O towards the kernel.

module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

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

   function transmit (address, size)
      local descindex = init_transmit_descriptor(address, size)
      assert(descindex < C.VIO_VRING_SIZE)
      txring.avail.ring[next_tx_avail % C.VIO_VRING_SIZE] = descindex
      next_tx_avail = (next_tx_avail + 1) % 65536
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
      table.insert(tx_freelist, txring.used.ring[txused % C.VIO_VRING_SIZE].id)
      assert(#tx_freelist <= C.VIO_VRING_SIZE)
      txused = (txused + 1) % 65536
      txpackets = txpackets + 1
   end M.reclaim_buffer = reclaim_buffer

   function sync_transmit ()
      C.full_memory_barrier()  txring.avail.idx = next_tx_avail  kick(txring)
   end M.sync_transmit = sync_transmit

   function can_transmit ()
      if tx_freelist[1] == nil then return nil, 'no free descriptors'
      else return true end
   end M.can_transmit = can_transmit

   local next_rx_avail = 0 -- Next available position in the rx avail ring

   function add_receive_buffer (address, size)
      local bufferindex = get_rx_buffer()
      assert(bufferindex < C.VIO_VRING_SIZE)
      local desc = rxring.desc[bufferindex]
      desc.addr, desc.len = ffi.cast("uint64_t", address), size
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
      local length  = rxring.used.ring[rxused % C.VIO_VRING_SIZE].len
      local address = rxring.desc[index].addr
      rxused = (rxused + 1) % 65536
      table.insert(rx_freelist, index)
      assert(#rx_freelist <= C.VIO_VRING_SIZE)
      rxpackets = rxpackets + 1
      return address, length
   end M.receive = receive

   function can_receive ()
      return rxused ~= rxring.used.idx
   end M.can_receive = can_receive

   function sync_receive ()
      C.full_memory_barrier()  rxring.avail.idx = next_rx_avail  kick(rxring)
   end M.sync_receive = sync_receive

   -- Make all of our DMA memory usable as vhost packet buffers.
   function update_vhost_memory_map ()
      C.vhost_set_memory(vio, memory_regions())
   end

   -- Construct a vhost memory map for the kernel. The memory map
   -- includes all of our currently allocated DMA buffers and reuses
   -- the address space of this process. This means that we can use
   -- ordinary pointer addresses to DMA buffers in our vring
   -- descriptors.
   function memory_regions ()
      local vio_memory = ffi.new("struct vio_memory")
      local dma_regions = memory.dma_regions
      vio_memory.nregions = #dma_regions
      vio_memory.padding = 0
      local vio_index = 0
      for _,region in ipairs(dma_regions) do
         local r = vio_memory.regions + vio_index
         r.guest_phys_addr = region.address
         r.userspace_addr = region.address
         r.memory_size = region.size
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
   function M.selftest (opts)
      local secs = (opts and opts.secs) or 1
      local deadline = C.get_time_ns() + secs * 1e9
      local done = function () return C.get_time_ns() > deadline end
      print("Echoing packets for "..secs.." second(s).")
      repeat
         while can_add_receive_buffer() do
            add_receive_buffer(memory.dma_alloc(2048), 2048)
         end
         while can_transmit() and can_receive() do
            local address, length = receive()
            transmit(address, length)
         end
         sync_receive()
         sync_transmit()
	 while can_reclaim_buffer() do
	    reclaim_buffer()
	 end
      until done()
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

