
-- Don't fuse i+101 on x64.
-- Except if i is sign-extended to 64 bit or addressing is limited to 32 bit.
do
  local t = {}
  for i=-100,-1 do t[i+101] = 1 end
end

