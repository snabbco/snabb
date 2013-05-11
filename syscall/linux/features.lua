-- test for features at run time
-- we need to be able to test for features eg presense of syscalls, kernel features
-- we do not cache as this may change if capabilities change, modules are loaded etc
-- cache carefully if you like
-- TODO add metatable so can call if values not functions?

local S = require "syscall"

local features = {}

features.ipv6 = function()
  local s, err = S.socket("inet6", "dgram")
  if not s and err.AFNOSUPPORT then return false end
  if s then s:close() end
  return true
end

features.cap = setmetatable({},
  {__index =
    function(_, k)
      local cap = S.capget()
      return cap.effective[k]
    end,
  }
)

return features

