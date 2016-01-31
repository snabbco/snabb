
local function ffib(n)
  if n <= 2 then return n,1 end
  if n % 2 == 1 then
    local a,b = ffib((n-1)/2)
    local aa = a*a
    return aa+a*(b+b), aa+b*b
  else
    local a,b = ffib(n/2-1)
    local ab = a+b
    return ab*ab+a*a, (ab+b)*a
  end
end

local function fib(n)
  return (ffib(n))
end

if arg and arg[1] then
  local n = tonumber(arg and arg[1]) or 10
  io.write(string.format("Fib(%d): %.0f\n", n, fib(n)))
else
  assert(fib(40) == 165580141)
  assert(fib(39) == 102334155)
  assert(fib(77) == 8944394323791464)
end
