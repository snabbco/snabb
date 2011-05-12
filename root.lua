-- tests that need to be done as root

local S = require "syscall"

assert(S.acct())

local mem
size = 4096
mem, err = S.mmap(nil, size, S.PROT_READ, S.MAP_PRIVATE + S.MAP_ANONYMOUS, -1, 0)
assert(err == nil, err)
assert(S.mlock(mem, size))
assert(S.munlock(mem, size))
assert(S.munmap(mem, size))

assert(S.mlockall(S.MCL_CURRENT))
assert(S.munlockall())

