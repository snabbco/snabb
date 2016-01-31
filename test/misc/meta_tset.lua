
local t=setmetatable({}, {__newindex=function(t,k,v)
  rawset(t, k, 100-v)
end})

for i=1,100 do t[i] = i end
for i=1,100 do assert(t[i] == 100-i) end

for i=1,100 do t[i] = i end
for i=1,100 do assert(t[i] == i) end

for i=1,100 do t[i] = nil end
for i=1,100 do t[i] = i end
for i=1,100 do assert(t[i] == 100-i) end

