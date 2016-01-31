local function rot9r(n)
  local a,b,c,d,e,f,g,h,i=1,2,3,4,5,6,7,8,9
  for x=1,n do
    a,b,c,d,e,f,g,h,i=i,a,b,c,d,e,f,g,h
  end
  return table.concat{a,b,c,d,e,f,g,h,i}
end

local function rot9l(n)
  local a,b,c,d,e,f,g,h,i=1,2,3,4,5,6,7,8,9
  for x=1,n do
    a,b,c,d,e,f,g,h,i=b,c,d,e,f,g,h,i,a
  end
  return table.concat{a,b,c,d,e,f,g,h,i}
end

assert(rot9r(0) == "123456789")
assert(rot9r(10) == "912345678")
assert(rot9r(105) == "456789123")
assert(rot9r(0) == "123456789")
assert(rot9r(1) == "912345678")
assert(rot9r(2) == "891234567")
assert(rot9r(0) == "123456789")
assert(rot9r(1) == "912345678")
assert(rot9r(2) == "891234567")
assert(rot9r(105) == "456789123")

assert(rot9l(0) == "123456789")
assert(rot9l(10) == "234567891")
assert(rot9l(105) == "789123456")
assert(rot9l(0) == "123456789")
assert(rot9l(1) == "234567891")
assert(rot9l(2) == "345678912")
assert(rot9l(0) == "123456789")
assert(rot9l(1) == "234567891")
assert(rot9l(2) == "345678912")

assert(rot9r(100) == "912345678")
assert(rot9l(100) == "234567891")
