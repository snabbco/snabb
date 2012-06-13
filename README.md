# Linux system calls for LuaJIT

What? An FFI implementation of the Linux kernel ABI for LuaJIT.

Why? Making a C library for everything you want to bind is a pain, so I thought I would see what you could do without, and I want to do some low level system stuff in Lua.

Linux only? Not so easy to port to other Unixes, you need to check the types and constants are correct, and remove anything that is not in your C library (that applies also to any non glibc library too), and test. Patches accepted, but will probably need to restructure for maintainability. However you may well be better off using [LuaPosix](https://github.com/rrthomas/luaposix) if you want to write portable Unix code.

Requirements: Needs LuaJIT 2.0.0-beta9 or later. Generally tested using git head.

Also supports [luaffi](https://github.com/jmckaskill/luaffi) so you can use with standard Lua; all the tests now pass, have added some workarounds to support current issues in luaffi which could be removed but these are not performance critical or important now as all the major issues have been resolved. There may still be a few issues in code that is not exercised by the tests, but actually luaffi has fixed most of the issues that were coming up anyway now. This is now tested and working with Lua 5.1 and 5.2.

### Testing

The test script is quite comprehensive, though it does not test all the syscalls, as I assume they work, but it should stress the bindings. Tested on ARM, amd64, x86. Intend to get my ppc build machine back up one day, if you want this supported please ask. I do not currently have a mips box, if you want this can you suggest a suitable dev box.

Initial testing on uclibc, works on my configuration, but uclibc warns that ABI can depend on compile options, so please test. I thought uclibc used kernel structures for eg stat, but they seem to use the glibc ones now, so more compatible. If there are more compatibility issues I may move towards using more syscalls directly, now we have the syscall function. Other C libraries may need more changes; I intend to test musl libc once I have a working build.

Reworking the test script, it is a copy of my fork of [luaunit](https://github.com/justincormack/luaunit) which is updated to work on Lua 5.1 and 5.2. To avoid dependencies I am just copying and updating this into this repo.

## What is implemented?

Unfinished! Some syscalls missing, work in progress! The majority of calls are now there, let me know if you need some that is not.

No support for 64 bit file operations on a 32 bit system yet.

## What will be implemented?

The aim is to implement the Linux kernel interfaces. This includes the system calls, the most obvious API, but also all the other parts: netlink communication used for configuring network interfaces and similar (started, but most still to do), and the ioctl based interfaces, of which the termios and pty interfaces have been done so far, thanks to [bdowning](https://github.com/bdowning). The aim is to provide helpers that look more familiar than the native interfaces for the complex stuff.

## Note on man(3)

There are some commands that call libc interfaces in man(3). These include some helper functions (eg inet_aton) that should be rewritten in Lua at some point as they are fairly trivial, will be done soon. Also includes the termios stuff, where these are functions that are mostly just ioctl commands and using the pts mux, but glibc does do quite a bit of other stuff if you look at the strace output, and there may be reasons for rewriting these in Lua using system calls directly, not sure yet. If so this would not affect the exposed interfaces. This also applies to some calls in man(2) that glibc does not just do exactly what the syscall does, and we may use the underlying syscall directly.

### System calls (135)

open, close, creat, chdir, mkdir, rmdir, unlink, acct, chmod, link, umask, uname, gethostname, sethostname, getuid, geteuid, getpid, getppid, getgid, getegid, fork, execve, wait, waitpid, \_exit, signal, gettimeofday, settimeofday, time, clock\_getres, clock\_gettime, clock\_settime, sysinfo, read, write, pread, pwrite, lseek, send, sendto, sendmsg, recv, recvfrom, recvmsg, readv, writev, getsockopt, setsockopt, select, epoll\_create, epoll\_ctl, epoll_wait, sendfile, dup, fchdir, fsync, fdatasync, fcntl, fchmod, socket, socketpair, bind, listen, connect, accept, getsockname, getpeername, mmap, munmap, msync, mlock, munlock, mlockall, munlockall, mremap, madvise, pipe, access, getcwd, nanosleep, syscall, stat, fstat, lstat, ioctl, eventfd, truncate, ftruncate, pause, reboot, sync, shutdown, ksyslogctl, mount, umount,
nice, getpriority, setpriority, prctl, alarm, waitid, inotify\_init, inotify\_add\_watch, inotify\_rm\_watch, adjtimex, getrlimit, setrlimit, sigprocmask, sigpending,
sigsuspend, getsid, setsid, listxattr, llistxattr, flistxattr, setxattr, lsetxattr, fsetxattr, getxattr, lgetxattr, fgetxattr, removexattr, lremovexattr, fremovexattr,
readlink, splice, vmsplice, tee, signalfd, timerfd\_create, timerfd\_settime, timerfd\_gettime, posix\_fadvise, fallocate, readahead, poll,
getitimer, setitimer, sync\_file\_range,
io\_cancel, io\_destroy, io\_setup, io\_submit, io\_getevents

### Other functions

exit, inet\_aton, inet\_ntoa, inet\_pton, inet\_ntop,
cfgetispeed, cfgetospeed, cfsetispeed, cfsetospeed, cfsetspeed,
tcgetattr, tcsetattr, tcsendbreak, tcdrain, tcflush, tcflow, tcgetsid,
posix\_openpt, grantpt, unlockpt, ptsname

### Socket types

inet, inet6, unix, netlink (partial support, in progress)

### API

Basically what you expect, with the following notes. In general we explicitly return return parameters as it is more idiomatic.

All functions return two values, the return value, or true if there is not one other than success, then an error value. This makes it easy to write things like assert(fd:close()). The error type can be converted to a string message, or you can retrieve the errno, or test against a symbolic error name.

File descriptors are returned as a type not an integer. This is because they are garbage collected by default, ie if they go out of scope the file is closed. You can get the file descriptor using the fileno field. To disable the garbage collection you can call fd:nogc(), in which case you need to close the descriptors by hand. They also have methods for operations that take an fd, like close, fsync, read. You can use this type where an fd is required, or a numeric fd, or a string like "stderr". 

String conversions are not done automatically, you get a buffer back, you have to force a conversion. This is because interning strings is expensive if you do not need it. However if you do not supply a buffer for the return value, you will get a string in general as more useful.

Many functions that return structs return metatypes exposing additional methods, so you get the raw values eg `st_size` and a Lua number as `size`, and possibly some extra helpful methods, like `major` and `minor` from stat. As these are metamethods they have no overhead, so more can be added to make the interfaces easier to use.

Not yet supporting the 64 bit file operations for 32 bit architectures (lseek64 etc).

Constants should all be available, eg `L.SEEK_SET` etc. You can add to combine them. They are also available as strings, so "SEEK\_SET" will be converted to S.SEEK\_SET. You can miss off the "SEEK\_" prefix, and they are not case sensitive, so you can just use `fd:lseek(offset, "set")` for more concise and readable use. If multiple flags are allowed, they can be comma separated for logical OR, such as `S.mmap(nil, size, "read", "private, anonymous", -1, 0)`.

You do not need to use the numbered versions of functions, eg dup can do dup2 or dup3 by adding more arguments

getcwd returns the result in a buffer if one is passed, or as a Lua string otherwise, ie if called with no parameters.

Standard convenience macros are also provided, eg S.major(dev) to extract a major number from a device number.

bind does not require a length for the address type length, as it can work this out dynamically.

`uname` returns a Lua table with the returned strings in it. Similarly `getdents` returns directory entries as a table. However I am moving more to returning native ffi structures with metamethods as this is less overhead than converting to tables, so long as I can provide the same functionality. If you want a higher level interface you can add a wrapper.

The test cases are good examples until I do better documentation!

A few functions have arguments in a different order to make optional ones easier. This is a bit confusing sometimes, so check the examples or source code.

### Issues

Rework socket address returns, should not need to copy structure, just cast.

Other consistency issues: accepting tables for structs like adjtimex does is a nice model, use in other places.

Managing constants a lot of work, may divide into subtables

Should add friendly permissions naming, eg "rw" to mode flags.

Netlink sockets need more friendly API.

Should build more high level API, eg net.eth0:ip() etc. Like sysfs but with native methods I guess, and create etc. eg net:bridge("br0"). net.br0.ip = ....

Should add some tostring methods for some of these structures... just done ls so far. eg network interfaces should look like ip/ifconfig output.

Should split out more of the stuff that is not just system calls into utility package.

Add proper iterator support to fd, bridge etc. So bridge.bridges is an iterator? name issues if you can call bridge.br0() to create etc.
Also need more support for dealing with signals on syscalls.

buffer_t could take string as initialiser, would have to be function.

itimerspec should have some metamethods to get numeric times out of it.

accept should return fd-like structure, but with extra fields? Added a fileno field, so can use like fd, but does not have methods...

getsockopt should return table of flags

Generate C code to test size and offset of each struct

Siginfo support in sigaction not there yet, as confused by the kernel API.

only some of aio is working, needs some debugging before being used.

### Missing functions

pselect, ppoll
clock\_nanosleep, timer\_create, timer\_getoverrun
faccessat(2), fchmodat(2), fchownat(2), fstatat(2),  futimesat(2),  linkat(2),  mkdirat(2),  mknodat(2),
readlinkat(2), renameat(2), symlinkat(2), unlinkat(2), utimensat(2), mkfifoat(3)
sigqueue,
capset, capget
...



