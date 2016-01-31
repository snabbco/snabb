local function nsieve(m, isPrime)
 for i=2,m do isPrime[i] = true end
 local count = 0
 for i=2,m do
   if isPrime[i] then
     for k=i+i,m,i do isPrime[k] = false end
     count = count + 1
   end
 end
 return count
end

local flags = {}
if arg and arg[1] then
  local N = tonumber(arg and arg[1])
  io.write(string.format("Primes up to %8d %8d", N, nsieve(N,flags)), "\n")
else
  assert(nsieve(100, flags) == 25)
  assert(nsieve(12345, flags) == 1474)
end
