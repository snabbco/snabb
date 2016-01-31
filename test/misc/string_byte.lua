
local band, bor = bit.band, bit.bor
local byte = string.byte

-- Fixed slice [i,i+k] or overflow
do
  local s = "abcdefg"
  local x,y,z
  for j=100,107 do
    for i=1,j do x,y,z = byte("abcdefg", band(i, 7), band(i+2, 7)) end
    local a,b,c = byte("abcdefg", band(j, 7), band(j+2, 7))
    assert(x == a and y == b and z == c)
  end
  for j=100,107 do
    for i=1,j do x,y,z = byte(s, band(i, 7), band(i+2, 7)) end
    local a,b,c = byte(s, band(j, 7), band(j+2, 7))
    assert(x == a and y == b and z == c)
  end
end

-- Positive slice [i,len] or overflow
do
  local s = "abc"
  local x,y,z
  for j=100,107 do
    for i=1,j do x,y,z = byte("abc", band(i, 7), -1) end
    local a,b,c = byte("abc", band(j, 7), -1)
    assert(x == a and y == b and z == c)
  end
  for j=100,107 do
    for i=1,j do x,y,z = byte(s, band(i, 7), -1) end
    local a,b,c = byte(s, band(j, 7), -1)
    assert(x == a and y == b and z == c)
  end
end

-- Negative slice [-i,len] or underflow
do
  local s = "abc"
  local x,y,z
  for j=-100,-107,-1 do
    for i=-1,j,-1 do x,y,z = byte("abc", bor(i, -8), -1) end
    local a,b,c = byte("abc", bor(j, -8), -1)
    assert(x == a and y == b and z == c)
  end
  for j=-100,-107,-1 do
    for i=-1,j,-1 do x,y,z = byte(s, bor(i, -8), -1) end
    local a,b,c = byte(s, bor(j, -8), -1)
    assert(x == a and y == b and z == c)
  end
end

-- Positive slice [1,i] or overflow
do
  local s = "abc"
  local x,y,z
  for j=100,107 do
    for i=1,j do x,y,z = byte("abc", 1, band(i, 7)) end
    local a,b,c = byte("abc", 1, band(j, 7))
    assert(x == a and y == b and z == c)
  end
  for j=100,107 do
    for i=1,j do x,y,z = byte(s, 1, band(i, 7)) end
    local a,b,c = byte(s, 1, band(j, 7))
    assert(x == a and y == b and z == c)
  end
end

-- Negative slice [1,-i] or underflow
do
  local s = "abc"
  local x,y,z
  for j=-100,-107,-1 do
    for i=-1,j,-1 do x,y,z = byte("abc", 1, bor(i, -8)) end
    local a,b,c = byte("abc", 1, bor(j, -8))
    assert(x == a and y == b and z == c)
  end
  for j=-100,-107,-1 do
    for i=-1,j,-1 do x,y,z = byte(s, 1, bor(i, -8)) end
    local a,b,c = byte(s, 1, bor(j, -8))
    assert(x == a and y == b and z == c)
  end
end

-- Check for slot stack overflow
do
  local s = string.rep("x", 500)
  for i=1,100 do byte(s, 1, 500) end
end

