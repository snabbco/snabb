local function rot9r(n, m)
  local a,b,c,d,e,f,g,h,i=1,2,3,4,5,6,7,8,9
  local s = ""
  for x=1,n do
    a,b,c,d,e,f,g,h,i=i,a,b,c,d,e,f,g,h
    if x == m then s = table.concat{a,b,c,d,e,f,g,h,i} end
    c,d = d,c
  end
  return table.concat{a,b,c,d,e,f,g,h,i, s}
end

assert(rot9r(0,0) == "123456789")
assert(rot9r(10,0) == "893124567")
assert(rot9r(105,0) == "913245678")
assert(rot9r(105,90) == "913245678891324567")
assert(rot9r(0,0) == "123456789")
assert(rot9r(1,0) == "913245678")
assert(rot9r(2,0) == "893124567")
assert(rot9r(1,1) == "913245678912345678")
assert(rot9r(2,1) == "893124567912345678")
assert(rot9r(2,2) == "893124567891324567")
