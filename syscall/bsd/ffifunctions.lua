-- define general BSD system calls for ffi

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local cdef = require "ffi".cdef

cdef[[
int getdirentries(int fd, char *buf, int nbytes, long *basep);
int unmount(const char *dir, int flags);
int revoke(const char *path);
int chflags(const char *path, unsigned long flags);
int lchflags(const char *path, unsigned long flags);
int fchflags(int fd, unsigned long flags);
int chflagsat(int fd, const char *path, unsigned long flags, int atflag);
long pathconf(const char *path, int name);
long lpathconf(const char *path, int name);
long fpathconf(int fd, int name);
int kqueue(void);
int kqueue1(int flags);
int kevent(int kq, const struct kevent *changelist, size_t nchanges, struct kevent *eventlist, size_t nevents, const struct timespec *timeout);
int issetugid(void);
int ktrace(const char *tracefile, int ops, int trpoints, pid_t pid);
]]

