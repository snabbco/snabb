
local assert = assert

-- DCE or sink trivial TNEW or TDUP.
do
  for i=1,100 do local t={} end
  for i=1,100 do local t={1} end
end

-- Sink TNEW/TDUP + ASTORE/HSTORE.
do
  for i=1,100 do local t={i}; assert(t[1] == i) end
  for i=1,100 do local t={foo=i}; assert(t.foo == i) end
  for i=1,100 do local t={1,i}; assert(t[2] == i) end
  for i=1,100 do local t={bar=1,foo=i}; assert(t.foo == i) end
end

-- Sink outermost table of nested TNEW.
do
  local x
  for i=1,100 do
    local t = {[0]={{1,i}}}
    if i == 90 then x = t end
    assert(t[0][1][2] == i)
  end
  assert(x[0][1][2] == 90)
  for i=1,100 do
    local t = {foo={bar={baz=i}}}
    if i == 90 then x = t end
    assert(t.foo.bar.baz == i)
  end
  assert(x.foo.bar.baz == 90)
end

-- Sink one TNEW + FSTORE.
do
  for i=1,100 do local t = setmetatable({}, {}) end
end

-- Sink TDUP or TDUP + HSTORE. Guard of HREFK eliminated.
do
  local x
  for i=1,100 do local t = { foo = 1 }; x = t.foo; end
  assert(x == 1)
  for i=1,100 do local t = { foo = i }; x = t.foo; end
  assert(x == 100)
end

-- Sink of simplified complex add, unused in next iteration, drop PHI.
do
  local x={1,2}
  for i=1,100 do x = {x[1]+3, x[2]+4} end
  assert(x[1] == 301)
  assert(x[2] == 402)
end

-- Sink of complex add, unused in next iteration, drop PHI.
do
  local x,k={1.5,2.5},{3.5,4.5}
  for i=1,100 do x = {x[1]+k[1], x[2]+k[2]} end
  assert(x[1] == 351.5)
  assert(x[2] == 452.5)
end

-- Sink of TDUP with stored values that are both PHI and non-PHI.
do
  local x,k={1,2},{3,4}
  for i=1,100 do x = {x[1]+k[1], k[2]} end
  assert(x[1] == 301)
  assert(x[2] == 4)
end

-- Sink of CONV.
do
  local t = {1}
  local x,y
  for i=1,200 do
    local v = {i}
    local w = {i+1}
    x = v[1]
    y = w[1]
    if i > 100 then end
  end
  assert(x == 200 and y == 201)
end

-- Sink of stores with numbers.
do
  local x = {1.5, 0}
  for i=1,200 do x = {x[1]+1, 99.5}; x[2]=4.5; if i > 100 then end end
  assert(x[1] == 201.5)
  assert(x[2] == 4.5)
end

-- Sink of stores with constants.
do
  for i=1,100 do local t = {false}; t[1] = true; if i > 100 then g=t end end
end

-- Sink with two references to the same table.
do
  for i=1,200 do
    local t = {i}
    local q = t
    if i > 100 then assert(t == q) end
  end
end

do
  local point
  point = {
    new = function(self, x, y)
      return setmetatable({x=x, y=y}, self)
    end,
    __add = function(a, b)
     return point:new(a.x + b.x, a.y + b.y)
    end,
  }
  point.__index = point
  local a, b = point:new(1, 1), point:new(2, 2)
  for i=1,100 do a = (a + b) + b end
  assert(a.x == 401)
  assert(a.y == 401)
  assert(getmetatable(a) == point)
  for i=1,200 do a = (a + b) + b; if i > 100 then end end
  assert(a.x == 1201)
  assert(a.y == 1201)
  assert(getmetatable(a) == point)
end

do
  local t = {}
  for i=1,20 do t[i] = 1 end
  for i=1,20 do
    for a,b in ipairs(t) do
      local s = {i}
    end
  end
end

