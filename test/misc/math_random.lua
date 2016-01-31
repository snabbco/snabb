
local random = math.random
local randomseed = math.randomseed

do
  local N = 1000
  local min, max = math.min, math.max
  for j=1,100 do
    randomseed(j)
    local lo, hi, sum = math.huge, -math.huge, 0
    for i=1,N do
      local x = random()
      sum = sum + x
      lo = min(lo, x)
      hi = max(hi, x)
    end
    assert(lo*N < 15 and (1-hi)*N < 15)
    assert(sum > N*0.45 and sum < N*0.55)
  end
end

