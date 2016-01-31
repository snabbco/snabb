
do
  local count = 0
  local t = setmetatable({ foo = nil },
    { __newindex=function() count = count + 1 end })
  for j=1,2 do
    for i=1,100 do t.foo = 1 end
    rawset(t, "foo", 1)
  end
  assert(count == 100)
end

do
  local count = 0
  local t = setmetatable({ nil },
    { __newindex=function() count = count + 1 end })
  for j=1,2 do
    for i=1,100 do t[1] = 1 end
    rawset(t, 1, 1)
  end
  assert(count == 100)
end

