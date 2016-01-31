
do
  local t = setmetatable({}, { __metatable = "foo" })
  for i=1,100 do assert(getmetatable(t) == "foo") end
end

do
  local mt = {}
  local t = setmetatable({}, mt)
  for i=1,100 do assert(getmetatable(t) == mt) end
  for i=1,100 do assert(setmetatable(t, mt) == t) end
end

do
  local mt = {}
  local t = {}
  for i=1,200 do t[i] = setmetatable({}, mt) end
  t[150] = setmetatable({}, { __metatable = "foo" })
  for i=1,200 do
    if not pcall(setmetatable, t[i], mt) then assert(i == 150) end
  end
  for i=1,200 do assert(getmetatable(t[i]) == mt or i == 150) end
  for i=1,200 do
    if not pcall(setmetatable, t[i], nil) then assert(i == 150) end
  end
  for i=1,200 do assert(getmetatable(t[i]) == nil or i == 150) end
end

do
  local x = true
  for i=1,100 do x = getmetatable(i) end
  assert(x == nil)
end

