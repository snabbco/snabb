local function fac(n)
  local x = 1
  for i=2,n do
    x = x * i
  end
  return x
end

if arg and arg[1] then
  print(fac(tonumber(arg[1])))
else
  assert(fac(10) == 3628800)
end
