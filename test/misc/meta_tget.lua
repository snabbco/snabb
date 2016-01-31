
local t=setmetatable({}, {__index=function(t,k)
  return 100-k
end})

for i=1,100 do assert(t[i] == 100-i) end

for i=1,100 do t[i] = i end
for i=1,100 do assert(t[i] == i) end

for i=1,100 do t[i] = nil end
for i=1,100 do assert(t[i] == 100-i) end


local x
local t2=setmetatable({}, {__index=function(t,k)
  x = k
end})

assert(t2[1] == nil)
assert(x == 1)

assert(t2.foo == nil)
assert(x == "foo")

