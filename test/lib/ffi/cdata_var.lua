local ffi = require("ffi")

do --- byte array allocations
  local typ = ffi.typeof"uint8_t[?]"
  for i = 4, 20 do
    for d = -3, 3 do
      local sz = 2^i + d
      assert(ffi.sizeof(typ, sz) == sz)
      local mem = ffi.new(typ, sz)
      assert(ffi.sizeof(mem) == sz)
      mem[0] = 0x21
      mem[1] = 0x32
      mem[2] = 0x43
      mem[sz-3] = 0x54
      mem[sz-2] = 0x65
      mem[sz-1] = 0x76
      assert(mem[0] == 0x21)
      assert(mem[1] == 0x32)
      assert(mem[2] == 0x43)
      assert(mem[sz-3] == 0x54)
      assert(mem[sz-2] == 0x65)
      assert(mem[sz-1] == 0x76)
    end
  end
end

do --- int array allocations
  local typ = ffi.typeof"int32_t[?]"
  for i = 2, 17 do
    for d = -2, 2 do
      local sz = 2^i + d
      assert(ffi.sizeof(typ, sz) == sz*4)
      local mem = ffi.new(typ, sz)
      assert(ffi.sizeof(mem) == sz*4)
      mem[0] = -3
      mem[sz-1] = -4
      assert(mem[0] == -3)
      assert(mem[sz-1] == -4)
    end
  end
end
