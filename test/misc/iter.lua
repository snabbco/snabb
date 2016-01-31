
do
  local n = 0
  for k,v in pairs(_G) do
    assert(_G[k] == v)
    n = n + 1
  end
  assert(n >= 40)
end

do
  local t = { 4,5,6,7,8,9,10 }
  local n = 0
  for i,v in ipairs(t) do
    assert(v == i+3)
    n = n + 1
  end
  assert(n == 7)
end

do
  local function count(t)
    local n = 0
    for i,v in pairs(t) do
      n = n + 1
    end
    return n;
  end
  assert(count({ 4,5,6,nil,8,nil,10}) == 5)
  assert(count({ [0] = 3, 4,5,6,nil,8,nil,10}) == 6)
  assert(count({ foo=1, bar=2, baz=3 }) == 3)
  assert(count({ foo=1, bar=2, baz=3, boo=4 }) == 4)
  assert(count({ 4,5,6,nil,8,nil,10, foo=1, bar=2, baz=3 }) == 8)
  local t = { foo=1, bar=2, baz=3, boo=4 }
  t.bar = nil; t.boo = nil
  assert(count(t) == 2)
end

do
  local t = {}
  for i=1,100 do t[i]=i end
  local n = 0
  for i,v in ipairs(t) do
    assert(i == v)
    n = n + 1
  end
  assert(n == 100)
end

do
  local ok, err = pcall(next, _G, 1)
  assert(not ok)
  local ok, err = pcall(function() next(_G, 1) end)
  assert(not ok)
end

do
  local t = {}
  local o = {{}, {}}
  for i=1,100 do
    local c = i..""
    t[i] = c
    o[1][c] = i
    o[2][c] = i
  end
  o[1]["90"] = nil

  for _, c in ipairs(t) do
    for i = 1, 2 do
      o[i][c] = o[i][c] or 1
    end
  end
end

do
  local t = { foo = 9, bar = 10, 4, 5, 6 }
  local r = {}
  local function dummy() end
  local function f(next)
    for k,v in next,t,nil do r[#r+1] = k; if v == 5 then f(dummy) end end
  end
  f(next)
  assert(#r == 5)
end

