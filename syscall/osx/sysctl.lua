--types for OSX sysctl, incomplete at present

local require = require

local c = require "syscall.osx.constants"

return {
  [c.CTL.KERN] = {
    [c.KERN.OSTYPE]    = "string",
    [c.KERN.OSRELEASE] = "string",
    [c.KERN.OSREV]     = "int",
    [c.KERN.VERSION]   = "string",
    [c.KERN.MAXVNODES] = "int",
    [c.KERN.MAXPROC]   = "int",
    [c.KERN.MAXFILES]  = "int",
    [c.KERN.ARGMAX]    = "int",
    [c.KERN.SECURELVL] = "int",
    [c.KERN.HOSTNAME]  = "string",
    [c.KERN.HOSTID]    = "int",
  }
}

