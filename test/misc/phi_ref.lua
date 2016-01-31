-- rref points into invariant part
do
  local x,y=1,2; for i=1,100 do x=x+y; y=i end
  assert(y == 100)
end

do
  local x,y=1,2; for i=1,100.5 do x=x+y; y=i end
  assert(y == 100)
end

do
  local x,y=1,2; for i=1,100 do x,y=y,x end
  assert(x == 1)
  assert(y == 2)
end

do
  local x,y,z=1,2,3; for i=1,100 do x,y,z=y,z,x end
  assert(x == 2)
  assert(y == 3)
  assert(z == 1)
end

do
  local x,y,z=1,2,3; for i=1,100 do x,y,z=z,x,y end
  assert(x == 3)
  assert(y == 1)
  assert(z == 2)
end

do
  local a,x,y,z=0,1,2,3; for i=1,100 do a=a+x; x=y; y=z; z=i end
  assert(a == 4759)
  assert(x == 98)
  assert(y == 99)
  assert(z == 100)
end

-- variant slot, but no corresponding SLOAD
do
  local x,y=1,2; for i=1,100 do x=i; y=i-1 end
  assert(x == 100)
  assert(y == 99)
end

do
  local x,y=1,2; for i=1,100 do x=i; y=i+1 end
  assert(x == 100)
  assert(y == 101)
end

do
  local x=0; for i=1,100 do if i==90 then break end x=i end
  assert(x == 89)
end

-- dup lref from variant slot (suppressed)
do
  local x,y=1,2; for i=1,100 do x=i; y=i end
  assert(x == 100)
  assert(y == 100)
end

-- const rref
do
  local x,y=1,2 local bxor,tobit=bit.bxor,bit.tobit;
  for i=1,100 do x=bxor(i,y); y=tobit(i+1) end
  assert(x == 0)
  assert(y == 101)
end

-- dup rref (ok)
do
  local x,y,z1,z2=1,2,3,4 local bxor,tobit=bit.bxor,bit.tobit;
  for i=1,100 do x=bxor(i,y); z2=tobit(i+5); z1=bxor(x,i+5); y=tobit(i+1) end
  assert(x == 0)
  assert(y == 101)
  assert(z1 == 105)
  assert(z2 == 105)
end

-- variant slot, no corresponding SLOAD,
do
  for i=1,5 do
    local a, b = 1, 2
    local bits = 0
    while a ~= b do
      bits = bits + 1
      a = b
      b = bit.lshift(b, 1)
    end
    assert(bits == 32)
  end
end

-- don't eliminate PHI if referenced from snapshot
do
  local t = { 0 }
  local a = 0
  for i=1,100 do
    local b = t[1]
    t[1] = i + a
    a = b
  end
  assert(a == 2500)
  assert(t[1] == 2550)
end

-- don't eliminate PHI if referenced from snapshot
do
  local x = 1
  local function f()
    local t = {}
    for i=1,200 do t[i] = i end
    for i=1,200 do
      local x1 = x
      x = t[i]
      if i > 100 then return x1 end
    end
  end
  assert(f() == 100)
end

-- don't eliminate PHI if referenced from another non-redundant PHI
do
  local t = {}
  for i=1,256 do
    local a, b, k = i, math.floor(i/2), -i
    while a > 1 and t[b] > k do
      t[a] = t[b]
      a = b
      b = math.floor(a/2)
    end
    t[a] = k
  end
  local x = 0
  for i=1,256 do x = x + bit.bxor(i, t[i]) end
  assert(x == -41704)
end

