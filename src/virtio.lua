-- intel.lua -- Intel 82574L driver with Linux integration
-- Copyright 2013 Luke Gorrie
-- Apache License 2.0: http://www.apache.org/licenses/LICENSE-2.0

module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

require("virtio_h")

function selftest ()
   local vio = ffi.new("struct vio")
   local buffer = memory.dma_alloc(2048)
   vio.tapfd = C.open_tap("");
   set_memory_regions(vio.memory)
   assert(C.vhost_setup(vio) == 0)
   vio.vring[0].desc[0].addr = ffi.cast("uint64_t", buffer)
   vio.vring[0].desc[0].len = 2048
   vio.vring[0].desc[0].flags = C.VIO_DESC_F_WRITE;
   vio.vring[0].avail.idx = 1;
   vio.vring[1].desc[0].addr = ffi.cast("uint64_t", buffer)
   vio.vring[1].desc[0].len = 2048
   vio.vring[1].desc[0].flags = C.VIO_DESC_F_WRITE;
   vio.vring[1].avail.idx = 1;
   while true do
      C.usleep(1000000)
      print_vio(vio)
      for i = 0, 16 do
	 io.write(bit.tohex(ffi.cast("int32_t*", buffer)[i]).." ")
      end
   end
end

-- Setup vhost DMA for all currently allocated chunks of DMA memory.
--
-- Specifically: tell the Linux kernel that addresses we use in the
-- virtio vring should be interpreted as being in the snabbswitch
-- process virtual address space, i.e. we will be using ordinary
-- pointer values (rather than, say, physical addresses).
function set_memory_regions (vio_memory)
--   local vio_memory = ffi.new("struct vio_memory")
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
--   assert( C.vhost_set_memory(sockfd, memory) == 0 )
end

function print_vio (vio)
   print("avail[0].idx:" .. tostring(vio.vring[0].avail.idx))
   print(" used[0].len:" .. tostring(vio.vring[0].used.len))
   print(" used[0].pktlen: " .. tostring(vio.vring[0].used.ring[0].len))
   print("avail[1].idx:" .. tostring(vio.vring[1].avail.idx))
   print(" used[1].len:" .. tostring(vio.vring[1].used.len))
end

