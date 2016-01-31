
local assert = assert

-- Same value ----------------------------------------------------------------

-- 1. Store with same ref and same value.
--    2nd store eliminated. All stores in loop eliminated.
do
  local t = { 1, 2 }
  for i=1,100 do
    t[1] = 11
    assert(t[1] == 11)
    t[1] = 11
    assert(t[1] == 11)
  end
  assert(t[1] == 11)
end

-- 2. Store with different tab, same idx and same value.
--    All stores in loop eliminated.
do
  local t1 = { 1, 2 }
  local t2 = { 1, 2 }
  for i=1,100 do
    t1[1] = 11
    assert(t1[1] == 11)
    t2[1] = 11
    assert(t2[1] == 11)
  end
  assert(t1[1] == 11)
  assert(t2[1] == 11)
end

-- 3. Store with same tab, different const idx and same value.
--    All stores in loop eliminated. Also disambiguated.
do
  local t = { 1, 2 }
  for i=1,100 do
    t[1] = 11
    assert(t[1] == 11)
    t[2] = 11
    assert(t[2] == 11)
  end
  assert(t[1] == 11)
  assert(t[2] == 11)
end

-- 4. Store with different tab, different const idx and same value.
--    All stores in loop eliminated. Also disambiguated.
do
  local t1 = { 1, 2 }
  local t2 = { 1, 2 }
  for i=1,100 do
    t1[1] = 11
    assert(t1[1] == 11)
    t2[2] = 11
    assert(t2[2] == 11)
  end
  assert(t1[1] == 11)
  assert(t2[2] == 11)
end

-- 5. Store with different tab, different non-const idx and same value.
--    All stores in loop eliminated. Not disambiguated (but not needed).
do
  local t1 = { 1, 2 }
  local t2 = { 1, 2 }
  local k = 1
  for i=1,100 do
    t1[k] = 11
    assert(t1[k] == 11)
    t2[2] = 11
    assert(t2[2] == 11)
  end
  assert(t1[1] == 11)
  assert(t2[2] == 11)
end

-- 6. Store with same ref, same value and aliased loads.
--    2nd store eliminated. Not disambiguated (but not needed).
do
  local t1 = { 1, 2 }
  local t2 = t1
  for i=1,100 do
    t1[1] = 11
    assert(t2[1] == 11)
    t1[1] = 11
    assert(t2[1] == 11)
  end
  assert(t1[1] == 11)
end

-- Different value -----------------------------------------------------------

-- 7. Store with same ref and different value.
--    1st store eliminated. All stores in loop eliminated.
do
  local t = { 1, 2 }
  for i=1,100 do
    assert(true)
    t[1] = 11
    assert(t[1] == 11)
    t[1] = 22
    assert(t[1] == 22)
  end
  assert(t[1] == 22)
end

-- 8. Store with different tab, same idx and different value.
--    Cannot eliminate any stores (would need dynamic disambiguation).
do
  local t1 = { 1, 2 }
  local t2 = { 1, 2 }
  for i=1,100 do
    assert(true)
    t1[1] = 11
    assert(t1[1] == 11)
    t2[1] = 22
    assert(t2[1] == 22)
  end
  assert(t1[1] == 11)
  assert(t2[1] == 22)
end

-- 9. Store with same tab, different const idx and different value.
--    Disambiguated. All stores in loop eliminated.
do
  local t = { 1, 2 }
  for i=1,100 do
    assert(true)
    t[1] = 11
    assert(t[1] == 11)
    t[2] = 22
    assert(t[2] == 22)
  end
  assert(t[1] == 11)
  assert(t[2] == 22)
end

-- 10. Store with different tab, different const idx and different value.
--     Disambiguated. All stores in loop eliminated.
do
  local t1 = { 1, 2 }
  local t2 = { 1, 2 }
  for i=1,100 do
    assert(true)
    t1[1] = 11
    assert(t1[1] == 11)
    t2[2] = 22
    assert(t2[2] == 22)
  end
  assert(t1[1] == 11)
  assert(t2[2] == 22)
end

-- 11. Store with different tab, different non-const idx and different value.
--     Cannot eliminate any stores (would need dynamic disambiguation).
do
  local t1 = { 1, 2 }
  local t2 = { 1, 2 }
  local k = 1
  for i=1,100 do
    assert(true)
    t1[k] = 11
    assert(t1[k] == 11)
    t2[2] = 22
    assert(t2[2] == 22)
  end
  assert(t1[1] == 11)
  assert(t2[2] == 22)
end

-- 12. Store with same ref, different value and aliased loads.
--     Cannot eliminate any stores (would need dynamic disambiguation).
do
  local t1 = { 1, 2 }
  local t2 = t1
  for i=1,100 do
    assert(true)
    t1[1] = 11
    assert(t2[1] == 11)
    t1[1] = 22
    assert(t2[1] == 22)
  end
  assert(t1[1] == 22)
end

-- CALLL must inhibit DSE.
do
  local a,b
  local t = {1,2}
  for i=1,100 do
    t[2]=nil
    a=#t
    t[2]=2
    b=#t
  end
  assert(a == 1 and b == 2)
end

