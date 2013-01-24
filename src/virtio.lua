-- intel.lua -- Intel 82574L driver with Linux integration
-- Copyright 2013 Luke Gorrie
-- Apache License 2.0: http://www.apache.org/licenses/LICENSE-2.0

module(...,package.seeall)

require("virtio_h")

function selftest ()
   local tapfd = C.open_tap("");
   local vhost = ffi.new("struct snabb_vhost")
   C.vhost_setup(tapfd, vhost)
   set_memory_regions()
end

-- Setup vhost DMA for all currently allocated chunks of DMA memory.
--
-- Specifically: tell the Linux kernel that addresses we use in the
-- virtio vring should be interpreted as being in the snabbswitch
-- process virtual address space, i.e. we will be using ordinary
-- pointer values (rather than, say, physical addresses).
function set_memory_regions (sockfd)
   local memory = ffi.new("struct vhost_memory")
   local dma_regions = memory.dma_regions
   memory.nregions = #dma_regions
   memory.padding = 0
   for i = 0, memory.nregions - 1 do
      local r = memory.regions[i]
      r.guest_phys_addr = memory.address
      r.userspace_addr = memory.address
      r.memory_size = memory.size
      r.flags_padding = 0
   end
   assert( C.vhost_set_memory(sockfd, memory) == 0 )
end

