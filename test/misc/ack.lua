local function Ack(m, n)
  if m == 0 then return n+1 end
  if n == 0 then return Ack(m-1, 1) end
  return Ack(m-1, (Ack(m, n-1))) -- The parentheses are deliberate.
end

if arg and arg[1] then
  local N = tonumber(arg and arg[1])
  io.write("Ack(3,", N ,"): ", Ack(3,N), "\n")
else
  assert(Ack(3,5) == 253)
end
