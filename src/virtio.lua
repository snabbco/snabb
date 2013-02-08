-- intel.lua -- Intel 82574L driver with Linux integration
-- Copyright 2013 Luke Gorrie
-- Apache License 2.0: http://www.apache.org/licenses/LICENSE-2.0

module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

require("virtio_h")

function new (tapinterface)

   local M = {}

   local vio = ffi.new("struct vio")
   local rx_freelist, tx_freelist
   local rxring, txring = vio.vring[0], vio.vring[1]

   function init ()
      rx_freelist, tx_freelist = {}, {}
      for i = 0, C.VIO_VRING_SIZE-2 do
	 rx_freelist[i+1] = i
	 tx_freelist[i+1] = i
      end
   end M.init = init

   -- Setup vhost DMA for all currently allocated chunks of DMA memory.
   --
   -- Specifically: tell the Linux kernel that addresses we use in the
   -- virtio vring should be interpreted as being in the snabbswitch
   -- process virtual address space, i.e. we will be using ordinary
   -- pointer values (rather than, say, physical addresses).
   function memory_regions ()
      local vio_memory = ffi.new("struct vio_memory")
      local dma_regions = memory.dma_regions
      vio_memory.nregions = #dma_regions
      vio_memory.padding = 0
      local vio_index = 0
      print("regions = " .. #dma_regions)
      for _,region in ipairs(dma_regions) do
	 local r = vio_memory.regions + vio_index
	 print(region.address, region.size)
	 r.guest_phys_addr = region.address
	 r.userspace_addr = region.address
	 r.memory_size = region.size
	 r.flags_padding = 0
	 vio_index = vio_index + 1
      end
      return vio_memory
   end

   function print_vio (vio)
      print("avail[0].idx:" .. tostring(vio.vring[0].avail.idx))
      print(" used[0].idx:" .. tostring(vio.vring[0].used.idx))
      print(" used[0].pktlen: " .. tostring(vio.vring[0].used.ring[0].len))
      print("avail[1].idx:" .. tostring(vio.vring[1].avail.idx))
      print(" used[1].idx:" .. tostring(vio.vring[1].used.idx))
   end

   local next_tx_avail = 0 -- Next available position in the tx avail ring

   function transmit (address, size)
      local bufferindex = get_transmit_buffer()
      local desc = txring.desc[bufferindex]
      desc.addr, desc.len = address, size
      desc.flags, desc.next = 0, 0
      txring.avail.ring[next_tx_avail] = bufferindex
      next_tx_avail = (next_tx_avail + 1) % C.VIO_VRING_SIZE
   end M.transmit = transmit

   -- Return the index of an available transmit buffer, or nil.
   function get_transmit_buffer ()
      if tx_freelist[1] == nil then reclaim_transmit_buffers() end
      return table.remove(tx_freelist)
   end

   local txused = 0
   function reclaim_transmit_buffers ()
      while txused ~= txring.used.idx do
	 table.insert(tx_freelist, txring.used.ring[idx].id)
	 txused = (txused + 1) % C.VIO_VRING_SIZE
      end
   end

   function sync_transmit ()
      C.full_memory_barrier()
      txring.avail.idx = next_tx_avail
      kick()
   end M.sync_transmit = sync_transmit

   function transmit_ready ()
      if tx_freelist[1] == nil then return nil, 'no free descriptors'
      else return true end
   end M.transmit_ready = transmit_ready

   local next_rx_avail = 0 -- Next available position in the rx avail ring

   function add_rxbuf (address, size)
      local bufferindex = get_rx_buffer()
      local desc = rxring.desc[bufferindex]
      desc.addr, desc.len = ffi.cast("uint64_t", address), size
      desc.flags, desc.next = C.VIO_DESC_F_WRITE, 0
      next_rx_avail = (next_rx_avail + 1) % C.VIO_VRING_SIZE
   end M.add_rxbuf = add_rxbuf

   function get_rx_buffer ()
      if rx_freelist[1] == nil then reclaim_receive_buffers() end
      return table.remove(rx_freelist)
   end

   local rxused = 0
   function reclaim_receive_buffers ()
      while rxused ~= rxring.used.idx do
	 table.insert(rx_freelist, rxring.used.ring[idx].id)
	 rxused = (rxused + 1) % C.VIO_VRING_SIZE
      end
   end

   -- Is there a receive descriptor available to store a new buffer in? [XXX name]
   function receive_buffer_ready ()
      return rx_freelist[1] ~= nil
   end M.receive_buffer_ready = receive_buffer_ready

   local rxused = 0		-- Next unprocessed index in the used ring
   function receive ()
      if rxused ~= rxring.used.idx then
	 print("receive rxused="..rxused.." used.idx="..(rxring.used.idx))
	 print_vio(vio)
	 print("a")
	 local index = rxring.used.ring[rxused].id
	 print("b")
	 local length  = rxring.used.ring[rxused].len
	 print("c index = " .. index)
	 local address = rxring.desc[index].addr
	 print("d")
	 table.insert(rx_freelist, index)
	 print("e")
	 rxused = (rxused + 1) % C.VIO_VRING_SIZE
	 print("f")
	 return address, length
      end
   end M.receive = receive

   function receive_packet_ready ()
      return rxused ~= rxring.used.idx
   end M.receive_packet_ready = receive_packet_ready

   function flush_rx()
      C.full_memory_barrier()
      rxring.avail.idx = next_rx_avail
   end M.flush_rx = flush_rx

   function M.selftest ()
      local buffer = memory.dma_alloc(2048)
      local tapfd = C.open_tap(tapinterface);
      assert(C.vhost_open(vio, tapfd, memory_regions()) == 0)
      rxring.desc[0].addr = ffi.cast("uint64_t", buffer)
      rxring.desc[0].len = 2048
      rxring.desc[0].flags = C.VIO_DESC_F_WRITE;
      rxring.avail.idx = 1;
      while true do
	 C.usleep(1000000)
	 print_vio(vio)
	 for i = 0, 16 do
	    io.write(bit.tohex(ffi.cast("int32_t*", buffer)[i]).." ")
	 end
	 txring.desc[0].addr = ffi.cast("uint64_t", buffer)
	 txring.desc[0].len = rxring.used.ring[0].len
      end
   end

   -- Write each received frame back onto the network.
   function M.echotest ()
      local buffer = memory.dma_alloc(2048)
      local tapfd = C.open_tap(tapinterface);
      assert(C.vhost_open(vio, tapfd, memory_regions()) == 0)
      while true do
	 while receive_buffer_ready() do
	    print("adding a buffer")
	    add_rxbuf(memory.dma_alloc(2048), 2048)
--	    C.vhost_set_memory(vio, memory_regions())
	 end
	 flush_rx()
	 while receive_packet_ready() do
	    print "Got a packet!"
	    local address, length = receive()
	    print("Length " .. length)
	    transmit(address, length)
	 end
	 sync_transmit()
--	 print_vio(vio)
--	 for i = 0, 16 do
--	    io.write(bit.tohex(ffi.cast("int32_t*", buffer)[i]).." ")
--	 end
--	 print()
	 C.usleep(1e3)
      end
   end

   function kick ()
      local value = ffi.new("uint64_t[1]")
      value[0] = 1
      C.write(vio.kickfd, value, 8)
   end

   return M
end

