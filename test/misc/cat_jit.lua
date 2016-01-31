
-- Constant folding
do
  local y
  for i=1,100 do y = "a".."b" end
  assert(y == "ab")
  for i=1,100 do y = "ab"..(1).."cd"..(1.5) end
  assert(y == "ab1cd1.5")
end

-- Fuse conversions to strings
do
  local y
  local x = "a"
  for i=1,100 do y = x..i end
  assert(y == "a100")
  x = "a"
  for i=1.5,100.5 do y = x..i end
  assert(y == "a100.5")
end

-- Fuse string construction
do
  local y
  local x = "abc"
  for i=1,100 do y = "x"..string.sub(x, 2) end
  assert(y == "xbc")
end

-- CSE, sink
do
  local y
  local x = "a"
  for i=1,100 do y = x.."b" end
  assert(y == "ab")
end

-- CSE, two buffers in parallel, no sink
do
  local y, z
  local x1, x2 = "xx", "yy"
  for i=1,100 do y = x1.."a"..x1; z = x1.."a"..x2 end
  assert(y == "xxaxx")
  assert(z == "xxayy")
  x1 = "xx"
  for i=1,100 do y = x1.."a"..x1; z = x1.."b"..x1 end
  assert(y == "xxaxx")
  assert(z == "xxbxx")
end

-- Append, CSE
do
  local y, z
  local x = "a"
  for i=1,100 do
    y = x.."b"
    y = y.."c"
  end
  assert(y == "abc")
  x = "a"
  for i=1,100 do
    y = x.."b"
    z = y.."c"
  end
  assert(y == "ab")
  assert(z == "abc")
  x = "a"
  for i=1,100 do
    y = x.."b"
    z = y..i
  end
  assert(y == "ab")
  assert(z == "ab100")
end

-- Append, FOLD
do
  local a, b = "x"
  for i=1,100 do b = (a.."y").."" end
  assert(b == "xy")
end

-- Append to buffer, sink
do
  local x = "a"
  for i=1,100 do x = x.."b" end
  assert(x == "a"..string.rep("b", 100))
  x = "a"
  for i=1,100 do x = x.."bc" end
  assert(x == "a"..string.rep("bc", 100))
end

-- Append to two buffers in parallel, no append, no sink
do
  local y, z = "xx", "yy"
  for i=1,100 do y = y.."a"; z = z.."b" end
  assert(y == "xx"..string.rep("a", 100))
  assert(z == "yy"..string.rep("b", 100))
end

-- Sink into side-exit
do
  local x = "a"
  local z
  for i=1,200 do
    local y = x.."b"
    if i > 100 then
      z = y..i
    end
  end
  assert(z == "ab200")
end

