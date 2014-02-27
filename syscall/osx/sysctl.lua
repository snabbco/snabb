--types for OSX sysctl, incomplete at present

local require = require

local c = require "syscall.osx.constants"

local map = {
  [c.CTL.KERN] = c.KERN,
}

local map2 = {}

local types = {
  ["kern.ostype"]    = "string",
  ["kern.osrelease"] = "string",
  ["kern.osrev"]     = "int",
  ["kern.version"]   = "string",
  ["kern.maxvnodes"] = "int",
  ["kern.maxproc"]   = "int",
  ["kern.maxfiles"]  = "int",
  ["kern.argmax"]    = "int",
  ["kern.securelvl"] = "int",
  ["kern.hostname"]  = "string",
  ["kern.hostid"]    = "int",
}

return {types = types, map = map, map2 = map2}


