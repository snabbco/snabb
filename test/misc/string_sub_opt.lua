
do
  local s = "abcde"
  local x = 0
  for i=1,100 do
    if string.sub(s, 1, 1) == "a" then x = x + 1 end
  end
  assert(x == 100)
end

do
  local s = "abcde"
  local x = 0
  for i=1,100 do
    if string.sub(s, 1, 1) == "b" then x = x + 1 end
  end
  assert(x == 0)
end

do
  local s = "abcde"
  local x = 0
  for i=1,100 do
    if string.sub(s, 1, 1) == "ab" then x = x + 1 end
  end
  assert(x == 0)
end

do
  local s = "abcde"
  local x = 0
  for i=1,100 do
    if string.sub(s, 1, 2) == "a" then x = x + 1 end
  end
  assert(x == 0)
end

do
  local s = "abcde"
  local x = 0
  local k = 1
  for i=1,100 do
    if string.sub(s, 1, k) == "a" then x = x + 1 end
  end
  assert(x == 100)
end

do
  local s = "abcde"
  local x = 0
  local k = 1
  for i=1,100 do
    if string.sub(s, 1, k) == "b" then x = x + 1 end
  end
  assert(x == 0)
end

do
  local s = "abcde"
  local x = 0
  local k = 1
  for i=1,100 do
    if string.sub(s, 1, k) == "ab" then x = x + 1 end
  end
  assert(x == 0)
end

----

do
  local s = "abcde"
  local x = 0
  for i=1,100 do
    if string.sub(s, 1, 2) == "ab" then x = x + 1 end
  end
  assert(x == 100)
end

do
  local s = "abcde"
  local x = 0
  for i=1,100 do
    if string.sub(s, 1, 3) == "abc" then x = x + 1 end
  end
  assert(x == 100)
end

do
  local s = "abcde"
  local x = 0
  for i=1,100 do
    if string.sub(s, 1, 4) == "abcd" then x = x + 1 end
  end
  assert(x == 100)
end

do
  local t = {}
  local line = string.rep("..XX", 100)
  local i = 1
  local c = line:sub(i, i)
  while c ~= "" and c ~= "Z" do
    t[i] = c == "X" and "Y" or c
    i = i + 1
    c = line:sub(i, i)
  end
  assert(table.concat(t) == string.rep("..YY", 100))
end

