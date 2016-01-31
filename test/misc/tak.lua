
local function tak(x, y, z)
  if y >= x then return z end
  return tak(tak(x-1, y, z), tak(y-1, z, x), (tak(z-1, x, y)))
end

if arg and arg[1] then
  local N = tonumber(arg and arg[1]) or 7
  print(tak(3*N, 2*N, N))
else
  assert(tak(21, 14, 7) == 14)
end
