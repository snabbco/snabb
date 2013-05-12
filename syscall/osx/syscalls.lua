-- BSD specific syscalls

return function(S, hh)

local c = require "syscall.constants"
local C = require "syscall.c"
local types = require "syscall.types"
local abi = require "syscall.abi"

function S.exit(status) C.exit(c.EXIT[status]) end
function S.mkfifo(pathname, mode) return retbool(C.mkfifo(pathname, c.S_I[mode])) end

return S

end

