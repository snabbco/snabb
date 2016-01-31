local function fib(n)
  if n < 2 then return 1 end
  return fib(n-2) + fib(n-1)
end

if arg and arg[1] then
  local n = tonumber(arg[1]) or 10
  io.write(string.format("Fib(%d): %d\n", n, fib(n)))
else
  assert(fib(27) == 317811)
end
