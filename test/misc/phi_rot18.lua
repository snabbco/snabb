local function rot18r(N)
  local a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r=1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18
  for x=1,N do
    a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r=r,a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q
  end
  return table.concat{a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r}
end

local function rot18l(N)
  local a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r=1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18
  for x=1,N do
    a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r=b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,a
  end
  return table.concat{a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r}
end

assert(rot18r(0)	== "123456789101112131415161718")
assert(rot18r(10)	== "910111213141516171812345678")
assert(rot18r(105)	== "456789101112131415161718123")
assert(rot18r(0)	== "123456789101112131415161718")
assert(rot18r(1)	== "181234567891011121314151617")
assert(rot18r(2)	== "171812345678910111213141516")
assert(rot18r(0)	== "123456789101112131415161718")
assert(rot18r(1)	== "181234567891011121314151617")
assert(rot18r(2)	== "171812345678910111213141516")
assert(rot18r(105)	== "456789101112131415161718123")

assert(rot18l(0)	== "123456789101112131415161718")
assert(rot18l(10)	== "111213141516171812345678910")
assert(rot18l(105)	== "161718123456789101112131415")
assert(rot18l(0)	== "123456789101112131415161718")
assert(rot18l(1)	== "234567891011121314151617181")
assert(rot18l(2)	== "345678910111213141516171812")
assert(rot18l(0)	== "123456789101112131415161718")
assert(rot18l(1)	== "234567891011121314151617181")
assert(rot18l(2)	== "345678910111213141516171812")

assert(rot18r(100)	== "910111213141516171812345678")
assert(rot18l(100)	== "111213141516171812345678910")
