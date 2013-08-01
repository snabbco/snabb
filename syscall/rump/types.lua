-- types for rump kernel
-- only called when not on NetBSD and using NetBSD types so needs types fixing up

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math

local function init(abi, c, errors, ostypes)

return require "syscall.types".init(abi, c, errors, ostypes)

end

return {init = init}


