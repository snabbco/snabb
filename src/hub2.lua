module(...,package.seeall)

local memory = require("memory")
local intel10g = require("intel10g")
local virtio = require("virtio")
local ffi = require("ffi")
local C = ffi.C

local vio

function init ()
   intel10g.open()
--   intel10g.enable_mac_loopback()
   intel10g.wait_linkup()
   vio = virtio.new("vio%d")
   vio.init()
end

-- Copy traffic between a virtio (tap) interface and a 10G NIC.
function test ()
   while true do
      transfer(vio, intel10g)
      transfer(intel10g, vio)
   end
end

-- Transfer packets from INPUT to OUTPUT.
function transfer (input, output)
   input.sync_receive()
   while input.can_receive() and output.can_transmit() do
      local addr, len = input.receive()
      output.transmit(addr, len)
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
   return (table.remove(freelist) or memory.dma_alloc(buffer_size)), buffer_size
end

-- Free a packet buffer for later reuse.
function free (buffer)
   table.insert(freelist, buffer)
end

