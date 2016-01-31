
do
  local y
  for i=1,100 do y = string.char(65) end
  assert(y == "A")
  local x = 97
  for i=1,100 do y = string.char(x) end
  assert(y == "a")
  x = "98"
  for i=1,100 do y = string.char(x) end
  assert(y == "b")
  for i=1,100 do y = string.char(32+i) end
  assert(y == "\132")
end

do
  local y
  assert(not pcall(function()
    for i=1,200 do y = string.char(100+i) end
  end))
  assert(y == "\255")
end

do
  local y
  for i=1,100 do y = string.char(65, 66, i, 67, 68) end
  assert(y == "ABdCD")
end
