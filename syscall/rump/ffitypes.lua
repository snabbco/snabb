-- This is only used if not running under NetBSD, in order to import the NetBSD types

local netbsd = require "syscall.netbsd.common.ffitypes"

netbsd.init(true) -- rump = true

