-- Benchmark code: asm ported to Lua

local ffi = require("ffi")
local C = ffi.C

local band = require("bit").band

ffi.cdef[[
struct ring {
  struct packet *packets[256];
  uint64_t read, write; // cursor positions
}
]]

local fl   = ffi.new("struct ring")
local source_to_tee = ffi.new("struct ring")
local tee1_to_sink  = ffi.new("struct ring")
local tee2_to_sink  = ffi.new("struct ring")

-- Populate the freelist
for i = 0, 255 do
   fl.packets[i] = ffi.cast("struct packet *",
                            memory.dma_alloc(ffi.sizeof("struct packet")))
   fl.write = i
end

local function source ()
   for i = 1, 100 do
      local p = fl.packets[band(fl.read, 255)]
      fl.read = fl.read + 1
      source_to_tee.packets[band(source_to_tee.write, 255)] = p
      source_to_tee.write = source_to_tee.write + 1
   end
end

local uint64_t = ffi.typeof("uint64_t *")

local function tee ()
   for i = 1, 100 do
      local p1 = source_to_tee.packets[band(source_to_tee.read, 255)]
      source_to_tee.read = source_to_tee.read + 1
      local p2 = fl.packets[band(fl.read, 255)]
      fl.read = fl.read + 1
      p2.length = p1.length
      local ptr1 = ffi.cast(uint64_t, p1.data)
      local ptr2 = ffi.cast(uint64_t, p2.data)
      -- 64 byte copy
      ffi.copy(ptr2, ptr1, 64)
--[[
      ptr2[0] = ptr1[0]
      ptr2[1] = ptr1[1]
      ptr2[2] = ptr1[2]
      ptr2[3] = ptr1[3]
      ptr2[4] = ptr1[4]
      ptr2[5] = ptr1[5]
      ptr2[6] = ptr1[6]
      ptr2[7] = ptr1[7]
--]]
      tee1_to_sink.packets[band(tee1_to_sink.write, 255)] = p1
      tee1_to_sink.write = tee1_to_sink.write + 1
      tee2_to_sink.packets[band(tee2_to_sink.write, 255)] = p2
      tee2_to_sink.write = tee2_to_sink.write + 1
   end
end

local function sink ()
   for i = 1, 100 do
      local p1 = tee1_to_sink.packets[band(tee1_to_sink.read, 255)]
      tee1_to_sink.read = tee1_to_sink.read + 1
      fl.packets[band(fl.write, 255)] = p1
      fl.write = fl.write + 1
      local p2 = tee2_to_sink.packets[band(tee2_to_sink.read, 255)]
      tee2_to_sink.read = tee2_to_sink.read + 1
      fl.packets[band(fl.write, 255)] = p2
      fl.write = fl.write + 1
   end
end

while source_to_tee.write < 1e9 do
   source() tee() sink()
end
