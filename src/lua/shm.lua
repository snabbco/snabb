-- Copyright 2012 Snabb GmbH. See the file LICENSE.

module(...,package.seeall)
require("pcap")

local ffi = require("ffi")
local C = ffi.C
local snabb = ffi.load("snabb")

ffi.cdef(io.open(os.getenv("SNABB").."/../QEMU/net/snabb-shm-dev.h"):read("*a"))
ffi.cdef(io.open(os.getenv("SNABB").."/src/c/snabb.h"):read("*a"))

-- Return true if `shm' is a valid shared memory packet device.
function check_shm_file (shm)
   return shm.magic == 0x57ABB000 and shm.version == 1
end

-- Return true if a packet is available.
function available (ring)
   return ring.tail ~= (ring.head + 1) % C.SHM_RING_SIZE
end

function full (ring)
   return ring.head == (ring.tail + 1) % C.SHM_RING_SIZE
end

-- Return the current shm_packet in the ring.
function packet (ring)
   return ring.packets[ring.head]
end

-- Advance to the next packet in the ring's head.
function advance_head (ring)
   ring.head = (ring.head + 1) % C.SHM_RING_SIZE
end

-- Advance to the next packet in the ring's tail.
function advance_tail (ring)
   ring.tail = (ring.tail + 1) % C.SHM_RING_SIZE
end


