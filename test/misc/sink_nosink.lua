
local assert = assert

-- Cannot sink TNEW, aliased load.
do
  local k = 1
  for i=1,100 do local t={i}; assert(t[k]==i) end
  for i=1,100 do local t={}; t[k]=i; assert(t[1]==i) end
end

-- Cannot sink TNEW, escaping to upvalue.
do
  (function()
    local uv
    return function()
      for i=1,100 do uv = {i} end
      assert(uv[1] == 100)
    end
  end)()()
end

-- Cannot sink TNEW, escaping through a store.
do
  local t = {}
  for i=1,100 do t[1] = {i} end
  for i=1,100 do t.foo = {i} end
  for i=1,100 do setmetatable(t, {i}) end
  assert(t[1][1] == 100)
  assert(t.foo[1] == 100)
  assert(getmetatable(t)[1] == 100)
end

-- Cannot sink TNEW, iteratively escaping through a store.
do
  local t = {}
  for i=1,100 do t[1] = {i}; t[1][1] = {i} end
  assert(t[1][1][1] == 100)
end

-- Cannot sink TNEW, escaping to next iteration (unused in 1st variant).
do
  local t;
  for i=1,200 do t = {i} end
  assert(t[1] == 200)
  for i=1,200 do if i > 100 then assert(t[1] == i-1) end t = {i} end
  assert(t[1] == 200)
end

-- Cannot sink TNEW, escaping to next iteration (snapshot ref).
do
  local t,x
  for i=1,100 do x=t; t={i} end
  assert(t[1] == 100)
  assert(x[1] == 99)
end

-- Cannot sink TNEW, escaping to next iteration (IR/snapshot ref).
do
  local t
  for i=1,100 do t={t} end
  assert(type(t[1][1][1]) == "table")
end

-- Could sink outer TNEW, but the logic for stores to PHI allocs is too simple.
-- Cannot sink inner TNEW, escaping to next iteration (IR ref).
do
  local t = {42, 43}
  for i=1,100 do t={t[2], {i}} end
  assert(t[2][1] == 100)
  assert(t[1][1] == 99)
end

-- Cannot sink TNEW, cross-PHI ref (and snapshot ref).
do
  local x,y
  for i=1,100 do x,y={i},x end
  assert(x[1] == 100)
  assert(y[1] == 99)
end

-- Cannot sink TNEW, cross-PHI ref (and snapshot ref).
do
  local x,y
  for i=1,100 do x,y=y,{i} end
  assert(x[1] == 99)
  assert(y[1] == 100)
end

-- Cannot sink TNEW, escaping to exit.
do
  local function f(n, t)
    if n == 0 then return t end
    return (f(n-1, {t}))
  end
  local t = f(100, 42)
  assert(type(t[1][1][1]) == "table")
  t = f(3, 42)
  assert(t[1][1][1] == 42)
end

-- Cannot sink TNEW, escaping to exit.
do
  local function f(n)
    if n == 0 then return 42 end
    local t = f(n-1)
    return {t}
  end
  for i=1,20 do
    local t = f(100)
    assert(type(t[1][1][1]) == "table")
  end
  t = f(3)
  assert(t[1][1][1] == 42)
end

-- Cannot sink, since nested inner table is non-PHI.
do
  local a, b = {{1}}, {{1}}
  for i=1,10000 do -- Need to force GC exit sometimes
    a = {{a[1][1]+b[1][1]}}
  end
  assert(a[1][1] == 10001)
end

