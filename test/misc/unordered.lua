
local function check(a, b)
  if a ~= b then
    error("check failed with "..tostring(a).." ~= "..tostring(b), 2)
  end
end

local x,y = 0/0,1

check(x<x,	false)
check(x<=x,	false)
check(x>x,	false)
check(x>=x,	false)
check(x==x,	false)
check(x~=x,	true)

check(x<y,	false)
check(x<=y,	false)
check(x>y,	false)
check(x>=y,	false)
check(x==y,	false)
check(x~=y,	true)

check(y<x,	false)
check(y<=x,	false)
check(y>x,	false)
check(y>=x,	false)
check(y==x,	false)
check(y~=x,	true)

check(x<1,	false)
check(x<=1,	false)
check(x>1,	false)
check(x>=1,	false)
check(x==1,	false)
check(x~=1,	true)

check(1<x,	false)
check(1<=x,	false)
check(1>x,	false)
check(1>=x,	false)
check(1==x,	false)
check(1~=x,	true)

check(not (x<x),	true)
check(not (x<=x),	true)
check(not (x>x),	true)
check(not (x>=x),	true)
check(not (x==x),	true)
check(not (x~=x),	false)

check(not (x<y),	true)
check(not (x<=y),	true)
check(not (x>y),	true)
check(not (x>=y),	true)
check(not (x==y),	true)
check(not (x~=y),	false)

check(not (y<x),	true)
check(not (y<=x),	true)
check(not (y>x),	true)
check(not (y>=x),	true)
check(not (y==x),	true)
check(not (y~=x),	false)

check(not (x<1),	true)
check(not (x<=1),	true)
check(not (x>1),	true)
check(not (x>=1),	true)
check(not (x==1),	true)
check(not (x~=1),	false)

check(not (1<x),	true)
check(not (1<=x),	true)
check(not (1>x),	true)
check(not (1>=x),	true)
check(not (1==x),	true)
check(not (1~=x),	false)

