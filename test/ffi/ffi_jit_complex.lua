local ffi = require("ffi")

local cx = ffi.typeof("complex")
local cxf = ffi.typeof("complex float")

ffi.cdef[[
typedef struct cc_t {
  struct cc_t *next;
  complex c;
} cc_t;
]]

do
  local c = cx(1, 2)
  local x
  for i=1,100 do
    x = c.re + c.im
  end
  assert(x == 3)
end

do
  local cp = ffi.new("cc_t")
  local p = cp
  p.next = p
  p.c = cx(1, 2)
  local x,y = 0,0
  for i=1,100 do
    x = x + p.c.re
    y = y + p.c.im
    p = p.next
  end
  assert(x == 100)
  assert(y == 200)
end

do
  local cp = ffi.new("cc_t")
  local p = cp
  p.next = p
  p.c = cx(1, 2)
  local x,y = 0,0
  for i=1,100 do
    x = x + p.c[0]
    y = y + p.c[1]
    p = p.next
  end
  assert(x == 100)
  assert(y == 200)
end

do
  local ca = ffi.new("complex[?]", 101)
  for i=1,100 do
    ca[i] = cx(i) -- handled as init single
  end
  local x,y = 0,0
  for i=1,100 do
    x = x + ca[i].re
    y = y + ca[i].im
  end
  assert(x == 5050)
  assert(y == 0)
end

do
  local ca = ffi.new("complex[?]", 101)
  for i=1,100 do
    ca[i] = cx(i, -i)
  end
  local x,y = 0,0
  for i=1,100 do
    x = x + ca[i].re
    y = y + ca[i].im
  end
  assert(x == 5050)
  assert(y == -5050)
end

do
  local ca = ffi.new("complex[?]", 101)
  local caf = ffi.new("complex float[?]", 101)
  for i=1,100 do
    ca[i] = cxf(i, -i)
    caf[i] = cx(i, -i)
  end
  local x,y = 0,0
  for i=1,100 do
    x = x + caf[i].re + ca[i].re
    y = y + caf[i].im + ca[i].im
  end
  assert(x == 2*5050)
  assert(y == -2*5050)
end

do
  local s = ffi.new("struct { complex x;}")
  for i=1,100 do
    s.x = 12.5i
  end
  assert(s.x.re == 0)
  assert(s.x.im == 12.5)
end

-- Index overflow for complex is ignored
do
  local c = cx(1, 2)
  local x
  for i=1e7,1e7+100 do x = c[i] end
end

