-- ioctls, filling in as needed

return function(abi, types)

local s = types.s

local strflag = require("syscall.helpers").strflag
local bit = require "bit"

local band = bit.band
local function bor(...)
  local r = bit.bor(...)
  if r < 0 then r = r + 4294967296LL end -- TODO see note in Linux
  return r
end
local lshift = bit.lshift
local rshift = bit.rshift

local ioctl = strflag {
}

return ioctl

end

