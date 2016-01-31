local function lt(x, y)
  if x < y then return true else return false end
end

local function le(x, y)
  if x <= y then return true else return false end
end

local function gt(x, y)
  if x > y then return true else return false end
end

local function ge(x, y)
  if x >= y then return true else return false end
end

local function eq(x, y)
  if x == y then return true else return false end
end

local function ne(x, y)
  if x ~= y then return true else return false end
end


local function ltx1(x)
  if x < 1 then return true else return false end
end

local function lex1(x)
  if x <= 1 then return true else return false end
end

local function gtx1(x)
  if x > 1 then return true else return false end
end

local function gex1(x)
  if x >= 1 then return true else return false end
end

local function eqx1(x)
  if x == 1 then return true else return false end
end

local function nex1(x)
  if x ~= 1 then return true else return false end
end


local function lt1x(x)
  if 1 < x then return true else return false end
end

local function le1x(x)
  if 1 <= x then return true else return false end
end

local function gt1x(x)
  if 1 > x then return true else return false end
end

local function ge1x(x)
  if 1 >= x then return true else return false end
end

local function eq1x(x)
  if 1 == x then return true else return false end
end

local function ne1x(x)
  if 1 ~= x then return true else return false end
end


local function check(a, b)
  if a ~= b then
    error("check failed with "..tostring(a).." ~= "..tostring(b), 2)
  end
end

local x,y = 1,2

check(x<y,	true)
check(x<=y,	true)
check(x>y,	false)
check(x>=y,	false)
check(x==y,	false)
check(x~=y,	true)

check(1<y,	true)
check(1<=y,	true)
check(1>y,	false)
check(1>=y,	false)
check(1==y,	false)
check(1~=y,	true)

check(x<2,	true)
check(x<=2,	true)
check(x>2,	false)
check(x>=2,	false)
check(x==2,	false)
check(x~=2,	true)

check(lt(x,y),	true)
check(le(x,y),	true)
check(gt(x,y),	false)
check(ge(x,y),	false)
check(eq(y,x),	false)
check(ne(y,x),	true)

local x,y = 2,1

check(x<y,	false)
check(x<=y,	false)
check(x>y,	true)
check(x>=y,	true)
check(x==y,	false)
check(x~=y,	true)

check(2<y,	false)
check(2<=y,	false)
check(2>y,	true)
check(2>=y,	true)
check(2==y,	false)
check(2~=y,	true)

check(x<1,	false)
check(x<=1,	false)
check(x>1,	true)
check(x>=1,	true)
check(x==1,	false)
check(x~=1,	true)

check(lt(x,y),	false)
check(le(x,y),	false)
check(gt(x,y),	true)
check(ge(x,y),	true)
check(eq(y,x),	false)
check(ne(y,x),	true)

local x,y = 1,1

check(x<y,	false)
check(x<=y,	true)
check(x>y,	false)
check(x>=y,	true)
check(x==y,	true)
check(x~=y,	false)

check(1<y,	false)
check(1<=y,	true)
check(1>y,	false)
check(1>=y,	true)
check(1==y,	true)
check(1~=y,	false)

check(x<1,	false)
check(x<=1,	true)
check(x>1,	false)
check(x>=1,	true)
check(x==1,	true)
check(x~=1,	false)

check(lt(x,y),	false)
check(le(x,y),	true)
check(gt(x,y),	false)
check(ge(x,y),	true)
check(eq(y,x),	true)
check(ne(y,x),	false)


check(lt1x(2),	true)
check(le1x(2),	true)
check(gt1x(2),	false)
check(ge1x(2),	false)
check(eq1x(2),	false)
check(ne1x(2),	true)

check(ltx1(2),	false)
check(lex1(2),	false)
check(gtx1(2),	true)
check(gex1(2),	true)
check(eqx1(2),	false)
check(nex1(2),	true)


check(lt1x(1),	false)
check(le1x(1),	true)
check(gt1x(1),	false)
check(ge1x(1),	true)
check(eq1x(1),	true)
check(ne1x(1),	false)

check(ltx1(1),	false)
check(lex1(1),	true)
check(gtx1(1),	false)
check(gex1(1),	true)
check(eqx1(1),	true)
check(nex1(1),	false)


check(lt1x(0),	false)
check(le1x(0),	false)
check(gt1x(0),	true)
check(ge1x(0),	true)
check(eq1x(0),	false)
check(ne1x(0),	true)

check(ltx1(0),	true)
check(lex1(0),	true)
check(gtx1(0),	false)
check(gex1(0),	false)
check(eqx1(0),	false)
check(nex1(0),	true)

do
  assert(not pcall(function()
    local a, b = 10.5, nil
    return a < b
  end))
end

do
  for i=1,100 do
    assert(bit.tobit(i+0x7fffffff) < 0)
  end
  for i=1,100 do
    assert(bit.tobit(i+0x7fffffff) <= 0)
  end
end

