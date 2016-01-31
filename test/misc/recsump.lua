
do
  local abs = math.abs
  local function sum(n)
    if n == 1 then return 1 end
    return abs(n + sum(n-1))
  end
  for i=1,tonumber(arg and arg[1]) or 100 do
    assert(sum(100) == 5050)
  end
end
