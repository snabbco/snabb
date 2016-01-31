
local band, bor = bit.band, bit.bor
local sub = string.sub

-- Positive slice [i,len] or overflow
do
  local s = "abc"
  local x
  for j=100,107 do
    for i=1,j do x = sub("abc", band(i, 7)) end
    assert(x == sub("abc", band(j, 7)))
  end
  for j=100,107 do
    for i=1,j do x = sub(s, band(i, 7)) end
    assert(x == sub(s, band(j, 7)))
  end
end

-- Negative slice [-i,len] or underflow
do
  local s = "abc"
  local x
  for j=-100,-107,-1 do
    for i=-1,j,-1 do x = sub("abc", bor(i, -8)) end
    assert(x == sub("abc", bor(j, -8)))
  end
  for j=-100,-107,-1 do
    for i=-1,j,-1 do x = sub(s, bor(i, -8)) end
    assert(x == sub(s, bor(j, -8)))
  end
end

-- Positive slice [1,i] or overflow
do
  local s = "abc"
  local x
  for j=100,107 do
    for i=1,j do x = sub("abc", 1, band(i, 7)) end
    assert(x == sub("abc", 1, band(j, 7)))
  end
  for j=100,107 do
    for i=1,j do x = sub(s, 1, band(i, 7)) end
    assert(x == sub(s, 1, band(j, 7)))
  end
end

-- Negative slice [1,-i] or underflow
do
  local s = "abc"
  local x
  for j=-100,-107,-1 do
    for i=-1,j,-1 do x = sub("abc", 1, bor(i, -8)) end
    assert(x == sub("abc", 1, bor(j, -8)))
  end
  for j=-100,-107,-1 do
    for i=-1,j,-1 do x = sub(s, 1, bor(i, -8)) end
    assert(x == sub(s, 1, bor(j, -8)))
  end
end

