-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local S = require("syscall")

local pause
local steps = 0
local target = 1000
local stepsize = 1

function stop ()
   collectgarbage('stop')
   pause = collectgarbage('setpause', 100)
end

function restart ()
   collectgarbage('setpause', pause)
   collectgarbage('restart')
end

function step ()
   steps = steps + 1
   if collectgarbage('step', steps) then
      --print(steps, target, stepsize)
      if steps > target then
         stepsize = stepsize * 2
         print(("GC for pid %d: increased step size to %d")
            :format(S.getpid(), stepsize))
      elseif stepsize > 1 and steps < target/2 then
         stepsize = stepsize / 2
         print(("GC for pid %d: decreased step size to %d")
            :format(S.getpid(), stepsize))
      end
      steps = 0
   end
end

function collect ()
   collectgarbage('collect')
end
