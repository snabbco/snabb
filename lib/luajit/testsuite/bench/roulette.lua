-- Russian Roulette simulator
-- This benchmark includes randomness from an external source that can
-- produce non-deterministic performance.
-- See https://github.com/LuaJIT/LuaJIT/issues/218

-- (Let the test harness determine the random seed)
-- math.randomseed(os.time())

local population = 200e6
local live = 0
local die  = 0

for i = 1, population do
   if math.random(6) == 6 then
      die = die + 1
   else
      live = live + 1
   end
end

print(("Survived %d/%d (%.3f%%)"):format(live, population, live*100/(live+die)))
