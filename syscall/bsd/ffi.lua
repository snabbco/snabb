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

int     extattrctl(const char *path, int cmd, const char *filename, int attrnamespace, const char *attrname);
int     extattr_delete_fd(int fd, int attrnamespace, const char *attrname);
int     extattr_delete_file(const char *path, int attrnamespace, const char *attrname);
int     extattr_delete_link(const char *path, int attrnamespace, const char *attrname);
ssize_t extattr_get_fd(int fd, int attrnamespace, const char *attrname, void *data, size_t nbytes);
ssize_t extattr_get_file(const char *path, int attrnamespace, const char *attrname, void *data, size_t nbytes);
ssize_t extattr_get_link(const char *path, int attrnamespace, const char *attrname, void *data, size_t nbytes);
ssize_t extattr_list_fd(int fd, int attrnamespace, void *data, size_t nbytes);
ssize_t extattr_list_file(const char *path, int attrnamespace, void *data, size_t nbytes);
ssize_t extattr_list_link(const char *path, int attrnamespace, void *data, size_t nbytes);
ssize_t extattr_set_fd(int fd, int attrnamespace, const char *attrname, const void *data, size_t nbytes);
ssize_t extattr_set_file(const char *path, int attrnamespace, const char *attrname, const void *data, size_t nbytes);
ssize_t extattr_set_link(const char *path, int attrnamespace, const char *attrname, const void *data, size_t nbytes);
]]

