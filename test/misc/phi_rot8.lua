local function rot8r(n)
  local a,b,c,d,e,f,g,h=1,2,3,4,5,6,7,8
  for x=1,n do
    a,b,c,d,e,f,g,h=h,a,b,c,d,e,f,g
  end
  return table.concat{a,b,c,d,e,f,g,h}
end

local function rot8l(n)
  local a,b,c,d,e,f,g,h=1,2,3,4,5,6,7,8
  for x=1,n do
    a,b,c,d,e,f,g,h=b,c,d,e,f,g,h,a
  end
  return table.concat{a,b,c,d,e,f,g,h}
end

assert(rot8r(0) == "12345678")
assert(rot8r(10) == "78123456")
assert(rot8r(105) == "81234567")
assert(rot8r(0) == "12345678")
assert(rot8r(1) == "81234567")
assert(rot8r(2) == "78123456")
assert(rot8r(0) == "12345678")
assert(rot8r(1) == "81234567")
assert(rot8r(2) == "78123456")
assert(rot8r(105) == "81234567")

assert(rot8l(0) == "12345678")
assert(rot8l(10) == "34567812")
assert(rot8l(105) == "23456781")
assert(rot8l(0) == "12345678")
assert(rot8l(1) == "23456781")
assert(rot8l(2) == "34567812")
assert(rot8l(0) == "12345678")
assert(rot8l(1) == "23456781")
assert(rot8l(2) == "34567812")

assert(rot8r(100) == "56781234")
assert(rot8l(100) == "56781234")
