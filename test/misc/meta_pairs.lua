
do
  local t = {}
  for i=1,10 do t[i] = i+100 end
  local a, b = 0, 0
  for j=1,100 do for k,v in ipairs(t) do a = a + k; b = b + v end end
  assert(a == 5500)
  assert(b == 105500)
  a, b = 0, 0
  for j=1,100 do for k,v in pairs(t) do a = a + k; b = b + v end end
  assert(a == 5500)
  assert(b == 105500)
end

do
  local t = setmetatable({}, {})
  for i=1,10 do t[i] = i+100 end
  local a, b = 0, 0
  for j=1,100 do for k,v in ipairs(t) do a = a + k; b = b + v end end
  assert(a == 5500)
  assert(b == 105500)
  a, b = 0, 0
  for j=1,100 do for k,v in pairs(t) do a = a + k; b = b + v end end
  assert(a == 5500)
  assert(b == 105500)
end

if os.getenv("LUA52") then
  local function iter(t, i)
    i = i + 1
    if t[i] then return i, t[i]+2 end
  end
  local function itergen(t)
    return iter, t, 0
  end
  local t = setmetatable({}, { __pairs = itergen, __ipairs = itergen })
  for i=1,10 do t[i] = i+100 end
  local a, b = 0, 0
  for j=1,100 do for k,v in ipairs(t) do a = a + k; b = b + v end end
  assert(a == 5500)
  assert(b == 107500)
  a, b = 0, 0
  for j=1,100 do for k,v in pairs(t) do a = a + k; b = b + v end end
  assert(a == 5500)
  assert(b == 107500)
end

