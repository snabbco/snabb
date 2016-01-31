
do
  local x = 0
  local t
  for i=1,1000 do
    if i >= 100 then
      -- causes an exit for atomic phase
      -- must not merge snapshot #0 with comparison since it has the wrong PC
      if i < 150 then x=x+1 end
      t = {i}
    end
  end
  assert(x == 50)
  assert(t[1] == 1000)
end

