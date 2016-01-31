
local t=setmetatable({}, {__newindex=function(t,k,v)
  assert(v == "foo"..k)
  rawset(t, k, "bar"..k)
end})

for i=1,100 do t[i]="foo"..i end
for i=1,100 do assert(t[i] == "bar"..i) end

for i=1,100 do t[i]="baz"..i end
for i=1,100 do assert(t[i] == "baz"..i) end

local t=setmetatable({foo=1,bar=1,baz=1},{})
t.baz=nil
t.baz=2
t.baz=nil
t.baz=2

