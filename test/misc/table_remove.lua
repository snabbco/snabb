
local tremove = table.remove
local assert = assert

do
  local t = {}
  for i=1,200 do t[i] = i end
  for i=1,100 do tremove(t) end
  assert(#t == 100 and t[100] == 100)
end

do
  local t = {}
  for i=1,200 do t[i] = i end
  for i=1,100 do assert(tremove(t) == 201-i) end
  assert(#t == 100 and t[100] == 100)
end

do
  local t = {}
  for i=1,200 do t[i] = i end
  for i=1,100 do assert(tremove(t, 1) == i) end
  assert(#t == 100 and t[100] == 200)
end

