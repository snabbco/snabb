local function f(i)
  local a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a;
  local a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a;
  local a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a;
  if i==90 then return end -- Exit needs to grow stack before slot fill.
end
for j=1,5 do
  collectgarbage() -- Shrink stack.
  for i=1,100 do f(i) end
end

local function g(i)
  if i==90 then return end -- Exit needs to grow stack after slot fill.
  do return end
  do
  local a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a;
  local a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a;
  local a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a;
  end
end
for j=1,5 do
  collectgarbage() -- Shrink stack.
  for i=1,100 do g(i) end
end
