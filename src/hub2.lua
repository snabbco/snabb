-- hub2.lua -- 2-port ethernet hub
-- Copyright 2013 Luke Gorrie <luke@snabb.co>
-- Apache License 2.0: http://www.apache.org/licenses/LICENSE-2.0

module(...,package.seeall)

local memory = require("memory")
local intel10g = require("intel10g")
local virtio = require("virtio").new("vio0")

-- Copy traffic between a virtio (tap) interface and a 10G NIC.
function test ()
   while true do
      transfer(intel10g, virtio)
      transfer(virtio, intel10g)
   end
end

-- Transfer packets from INPUT to OUTPUT.
function transfer (input, output)
   input.sync_receive()
   while input.can_receive() and output.can_transmit() do
      output.transmit(input.receive())
   end
   while input.can_add_receive_buffer() do
      input.add_receive_buffer(allocate())
   end
   while output.can_reclaim_buffer() do
      free(output.reclaim_buffer())
   end
   output.sync_transmit()
end

buffer_size = 2048
freelist = {}

-- Return a free packet buffer.
function allocate ()
   return table.remove(freelist) or dma_alloc()
end

-- Allocate a new packet buffer.
function dma_alloc ()
   local virt, phys = memory.dma_alloc(buffer_size)
   return phys
end

-- Free a packet buffer for later reuse.
function free (buffer)
   table.insert(freelist, buffer)
end

