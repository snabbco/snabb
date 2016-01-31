
local function create(equal, v1, v2)
  local meta = { __eq = equal }
  return setmetatable({v1}, meta), setmetatable({v2}, meta)
end

local xop
local a, b = create(function(a,b) xop = "eq" return "" end)
assert(a==b == true and xop == "eq"); xop = nil
assert(a~=b == false and xop == "eq"); xop = nil

-- Different metatable, but same metamethod works, too.
setmetatable(b, { __eq = getmetatable(b).__eq })
assert(a==b == true and xop == "eq"); xop = nil
assert(a~=b == false and xop == "eq"); xop = nil

local a, b = create(function(a,b) return a[1] == b[1] end, 1, 2)
assert(a==b == false)
assert(a~=b == true)

b[1] = 1
assert(a==b == true)
assert(a~=b == false)

a[1] = 2
assert(a==b == false)
assert(a~=b == true)


local function obj_eq(a, b)
  assert(a==b == true)
  assert(a~=b == false)
end

local function obj_ne(a, b)
  assert(a==b == false)
  assert(a~=b == true)
end

obj_eq(nil, nil)
obj_ne(nil, false)
obj_ne(nil, true)

obj_ne(false, nil)
obj_eq(false, false)
obj_ne(false, true)

obj_ne(true, nil)
obj_ne(true, false)
obj_eq(true, true)

obj_eq(1, 1)
obj_ne(1, 2)
obj_ne(2, 1)

obj_eq("a", "a")
obj_ne("a", "b")
obj_ne("a", 1)
obj_ne(1, "a")

local t, t2 = {}, {}
obj_eq(t, t)
obj_ne(t, t2)
obj_ne(t, 1)
obj_ne(t, "")

