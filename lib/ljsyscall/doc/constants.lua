-- Documentation of constants

-- Currently taken from FreeBSD man pages, so need Linux/NetBSD/OSX specific ones added

local d = {}

d.O = {
  RDONLY       = "open for reading only",
  WRONLY       = "open for writing only",
  RDWR         = "open for reading and writing",
  EXEC         = "open for execute only",
  NONBLOCK     = "do not block on open",
  APPEND       = "append on each write",
  CREAT        = "create file if it does not exist",
  TRUNC        = "truncate size to 0",
  EXCL         = "error if create and file exists",
  SHLOCK       = "atomically obtain a shared lock",
  EXLOCK       = "atomically obtain an exclusive lock",
  DIRECT       = "eliminate or reduce cache effects",
  FSYNC        = "synchronous writes",
  SYNC         = "synchronous writes",
  NOFOLLOW     = "do not follow symlinks",
  NOCTTY       = "don't assign controlling terminal",
  TTY_INIT     = "restore default terminal attributes",
  DIRECTORY    = "error if file is not a directory",
  CLOEXEC      = "set FD_CLOEXEC upon open", -- TODO should be hyperlink
}

return d

