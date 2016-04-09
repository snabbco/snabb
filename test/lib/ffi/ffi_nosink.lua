local ffi = require("ffi")

do
  local x = 0ll
  for i=1,100 do x=x+1; g=x end
  assert(x == 100ll)
  assert(g == 100ll)
end

do
  local x = 0ll
  for i=1,100 do local y=x; x=x+1; g=y end
  assert(x == 100ll)
  assert(g == 99ll)
end

do
  local x = 0ll
  local z
  for i=1,100 do z=x+1; g=z end
  assert(z == 1ll)
  assert(g == 1ll)
end

do
  local x,y = 0ll, 0ll
  for i=1,100 do y,x=x,x+1 end
  assert(x == 100ll)
  assert(y == 99ll)
end

do
  local st = ffi.typeof("struct { void *p; }")
  local x
  for i=1,100 do x = st(); x.p = x end
  assert(x.p == ffi.cast("void *", x))
end

do
  ffi.cdef[[char *strchr(char *, int);]]
  for i=1,100 do
    local p = ffi.new("char[2]");
    ffi.C.strchr(p, 32)
  end
end
