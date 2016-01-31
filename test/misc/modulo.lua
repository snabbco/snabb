
for x=-5,5 do
  for y=-5,5 do
    if y ~= 0 then
      assert(x%y == x-math.floor(x/y)*y)
    end
  end
end

for x=-5,5,0.25 do
  for y=-5,5,0.25 do
    if y ~= 0 then
      assert(x%y == x-math.floor(x/y)*y)
    end
  end
end

do
  local y = 0
  for x=-100,123 do
    y = y + x%17
  end
  assert(y == 1777)
end

do
  local y = 0
  for x=-100,123 do
    if x ~= 0 then
      y = y + 85%x
    end
  end
  assert(y == 2059)
end

do
  local x = 1%0
  assert(x ~= x)
  x = math.floor(0/0)
  assert(x ~= x)
end

