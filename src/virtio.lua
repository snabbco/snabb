-- intel.lua -- Intel 82574L driver with Linux integration
-- Copyright 2013 Luke Gorrie
-- Apache License 2.0: http://www.apache.org/licenses/LICENSE-2.0

module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

require("virtio_h")

function selftest ()
   local vio = ffi.new("struct vio")
   vio.tapfd = C.open_tap("");
   assert(C.vhost_setup(vio) == 0)
   set_memory_regions()
end

-- Setup vhost DMA for all currently allocated chunks of DMA memory.
--
-- Specifically: tell the Linux kernel that addresses we use in the
-- virtio vring should be interpreted as being in the snabbswitch
-- process virtual address space, i.e. we will be using ordinary
-- pointer values (rather than, say, physical addresses).
function set_memory_regions (sockfd)
   local vio_memory = ffi.new("struct vio_memory")
   local dma_regions = memory.dma_regions
   vio_memory.nregions = #dma_regions
   vio_memory.padding = 0
   local vio_index = 0
   for _,region in ipairs(dma_regions) do
      local r = vio_memory.regions[vio_index]
      r.guest_phys_addr = memory.address
      r.userspace_addr = memory.address
      r.memory_size = memory.size
      r.flags_padding = 0
      vio_index = i + 1
   end
--   assert( C.vhost_set_memory(sockfd, memory) == 0 )
end

