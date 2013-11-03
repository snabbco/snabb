-- these are constants for rump kernel
-- note these are internal constants, all the OS constants are NetBSD ones

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local h = require "syscall.helpers"

local octal, multiflags, charflags, swapflags, strflag, atflag, modeflags
  = h.octal, h.multiflags, h.charflags, h.swapflags, h.strflag, h.atflag, h.modeflags

local c = {}

c.ETFS = strflag {
  REG = 0,
  BLK = 1,
  CHR = 2,
  DIR = 3,
  DIR_SUBDIRS = 4,
}

c.RUMPUIO = strflag {
  READ = 0,
  WRITE = 1,
}

c.SIGMODEL = strflag {
  PANIC = 0,
  IGNORE = 1,
  HOST = 2,
  RAISE = 3,
  RECORD = 4,
};

c.RF = strflag {
  NONE    = 0x00, -- not named, see issue https://github.com/anttikantee/buildrump.sh/issues/19
  FDG     = 0x01,
  CFDG    = 0x02,
}

c.CN_FREECRED = 0x02
c.ETFS_SIZE_ENDOFF = h.uint64_max

return c

