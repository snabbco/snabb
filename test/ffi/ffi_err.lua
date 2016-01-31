local ffi = require("ffi")

-- error in FFI metamethod: don't print metamethod frame.
do
  local ok, err = xpcall(function()
    local x = (1ll).foo
  end, debug.traceback)
  assert(ok == false)
  assert(not string.find(err, "__index"))
end

-- tailcall in regular metamethod: keep metamethod frame.
do
  local ok, err = xpcall(function()
    local t = setmetatable({}, {__index = function() return rawget("x") end })
    local y = t[1]
  end, debug.traceback)
  assert(ok == false)
  assert(string.find(err, "__index"))
end

-- error in FFI metamethod: set correct PC.
do
  ffi.cdef[[
typedef struct { int x; int y; } point;
point strchr(point* op1, point* op2);
]]
  local point = ffi.metatype("point", { __add = ffi.C.strchr })
  local function foo()
    local p = point{ 3, 4 }
    local r = p + p
    local r = p + 5
  end
  local ok, err = xpcall(foo, debug.traceback)
  local line = debug.getinfo(foo).linedefined+3
  assert(string.match(err, "traceback:[^:]*:"..line..":"))
end

