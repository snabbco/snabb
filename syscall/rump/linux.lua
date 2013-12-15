-- If using Linux ABI compatibility we need a few extra types from NetBSD
-- TODO In theory we should not need these, just create a new NetBSD rump instance when we want them instead
-- currently just mount support

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(types, c)

require "syscall.netbsd.ffitypes"

local h = require "syscall.helpers"

local addtype = h.addtype

local addstructs = {
  ufs_args = "struct _netbsd_ufs_args",
  tmpfs_args = "struct _netbsd_tmpfs_args",
  ptyfs_args = "struct _netbsd_ptyfs_args",
}

for k, v in pairs(addstructs) do addtype(types, k, v, {}) end

return types

end

return {init = init}

