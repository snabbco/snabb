# Linux system calls for LuaJIT

What? An FFI implementation of the Linux kernel ABI for LuaJIT.

Why? Making a C library for everything you want to bind is a pain, so I thought I would see what you could do without, and I want to do some low level system stuff in Lua.

Linux only? Not so easy to port to other Unixes, you need to check the types and constants are correct, and remove anything that is not in your C library (that applies also to any non glibc library too), and test. Patches accepted, but will probably need to restructure for maintainability. However you may well be better off using [LuaPosix](https://github.com/rrthomas/luaposix) if you want to write portable Unix code.

Requirements: Needs LuaJIT 2.0.0-beta9 or later. Generally tested using git head.

Also supports [luaffi](https://github.com/jmckaskill/luaffi) so you can use with standard Lua; all the tests now pass, have added some workarounds to support current issues in luaffi which could be removed but these are not performance critical or important now as all the major issues have been resolved. There may still be a few issues in code that is not exercised by the tests, but actually luaffi has fixed most of the issues that were coming up anyway now. This is now tested and working with Lua 5.1 and 5.2.

Releases after tag 0.3 do not currently work with luaffi, please use that until fixed. Using new ffi features to simplify code.

### Testing

The test script is quite comprehensive, though it does not test all the syscalls, as I assume they work, but it should stress the bindings. Tested on ARM, amd64, x86. Intend to get my ppc build machine back up one day, if you want this supported please ask. I do not currently have a mips box, if you want this can you suggest a suitable dev box.

Some tests need to be run as root to do anything. They don't fail, but they do not do anything. You cannot test a lot of stuff otherwise. However most of the testing is now done in isolated containers so should be harmless. Need to move the bridge tests to a container.

Some tests may fail if you do not have kernel support for some feature (eg namespacing, ipv6, etc).

Initial testing on uclibc, at one point worked on my configuration, but uclibc warns that ABI can depend on compile options, so please test. I thought uclibc used kernel structures for eg stat, but they seem to use the glibc ones now, so more compatible. If there are more compatibility issues I may move towards using more syscalls directly, now we have the syscall function. Other C libraries may need more changes; I intend to test musl libc once I have a working build.

Reworking the test script, it is a copy of my fork of [luaunit](https://github.com/justincormack/luaunit) which is updated to work on Lua 5.1 and 5.2. To avoid dependencies I am just copying and updating this into this repo. Currently all my changes are upstream.

## What is implemented?

This project is in beta! Some syscalls are missing, this is a work in progress! The majority of syscalls are now there, let me know if you need some that are not.

The syscall API covers a lot of stuff, but there are other interfaces. There is now a small wrapper for the process interface (/proc).

Work on the netlink API is progressing. A lot of the code for bridges was done as a prototype, and now working on the interface for network interfaces. The read side of network interfaces is done, you can now do `print(S.get_interfaces()` to get something much like ifconfig returns, and all the raw data is there as Lua tables. Still to do are the write side of these interfaces, and the additional parts such as routing, but these should be quicker to implement now some is done, although these interfaces are quite large.

There is also a lot of the `ioctl` interfaces to implement, which are very miscellaneous. Mostly you just need some constants and typecasting, but helper functions are probably useful.

The termios and pty interfaces have been implemented, thanks to [bdowning](https://github.com/bdowning). These wrap the libc calls, which underneath are mostly `ioctl` interfaces plus interfaces to the `/dev/pty` devices.

The aim is to provide nice to use, Lua friendly interfaces where possible, but more work needs to be done, as have really started with the raw interfaces, but adding functionality through metatypes.

## Note on libc

Lots of system calls have glibc wrappers, some of these are trivial some less so. In particular some of them expose different ABIs, so we try to avoid, just using kernel ABIs as these have long term support. `strace` is your friend.

Currently I have done little testing on other C libraries that will help iron out these differences, but I intend to support at least uclibc and Musl eventually, which should help remove any glibc-isms.

### System calls

This list is now out of date.

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

All functions return two values, the return value, or true if there is not one other than success, then an error value. This makes it easy to write things like assert(fd:close()). The error type can be converted to a string message, or you can retrieve the errno, or test against a symbolic error name.

File descriptors are returned as a type not an integer. This is because they are garbage collected by default, ie if they go out of scope the file is closed. You can get the file descriptor using the fileno field. To disable the garbage collection you can call fd:nogc(), in which case you need to close the descriptors by hand. They also have methods for operations that take an fd, like close, fsync, read. You can use this type where an fd is required, or a numeric fd, or a string like "stderr". 

String conversions are not done automatically, you get a buffer back, you have to force a conversion. This is because interning strings is expensive if you do not need it. However if you do not supply a buffer for the return value, you will get a string in general as more useful.

Many functions that return structs return metatypes exposing additional methods, so you get the raw values eg `st_size` and a Lua number as `size`, and possibly some extra helpful methods, like `major` and `minor` from stat. As these are metamethods they have no overhead, so more can be added to make the interfaces easier to use.

Constants should all be available, eg `L.SEEK_SET` etc. You can add to combine them. They are also available as strings, so "SEEK\_SET" will be converted to S.SEEK\_SET. You can miss off the "SEEK\_" prefix, and they are not case sensitive, so you can just use `fd:lseek(offset, "set")` for more concise and readable use. If multiple flags are allowed, they can be comma separated for logical OR, such as `S.mmap(nil, size, "read", "private, anonymous", -1, 0)`.

You do not need to use the numbered versions of functions, eg dup can do dup2 or dup3 by adding more arguments

Standard convenience macros are also provided, eg S.major(dev) to extract a major number from a device number. Generally metamethods are also provided for these.

`bind` does not require a length for the address type length, as it can work this out dynamically.

`uname` returns a Lua table with the returned strings in it. Similarly `getdents` returns directory entries as a table. Other functions such as `poll` return an ffi metatype that behaves like a Lua array, ie is 1-indexed and has a `#` length method, which wraps the underlying C structure.

The test cases are good examples until I do better documentation!

A few functions have arguments in a different order to make optional ones easier. This is a bit confusing sometimes, so check the examples or source code.

It would be nice to be API compatible with other projects, especially Luaposix, and luasocket.

### Issues

Siginfo support in sigaction not there yet, as confused by the kernel API.

only some of aio is working, needs some debugging before being used. Also all the iocb functions should be replaced with metatypes eg getiocb, getiocbs.

There will no doubt be bugs, please report them if you find them.

### Missing functions etc

pselect, ppoll
clock\_nanosleep, timer\_create, timer\_getoverrun
faccessat(2), fchmodat(2), fchownat(2), fstatat(2),  futimesat(2),  linkat(2),  mkdirat(2),  mknodat(2),
readlinkat(2), renameat(2), symlinkat(2), unlinkat(2), utimensat(2), mkfifoat(3)
sigqueue,
capset, capget
pivot_root
...

### 64 bit fileops on 32 bit

These now work and have tests, the 64 bit operations are always used on 32 bit architectures.

Note that fcntl64 has not been changed yet, as we have not defined the flock structure which is the change, and it is wrapped by glibc. statfs is also wrapped by glibc.

### uid size.
Linux 2.4 increased the size of user and group IDs from 16 to 32 bits.  Tosupport this change, a range of system calls were added (e.g., chown32(2),getuid32(2), getgroups32(2), setresuid32(2)), superseding earlier calls ofthe same name without the "32" suffix.

The glibc wrappers hide this, and call the 32 bit calls anyway, so should be ok.

## fcntl
Some helper functions for fcntl features such as file locking should be added?

## sysctl
Need a trivial sysctl wrapper (write to /proc/sys)

## cgroups
Need a cgroup interface.

## netlink
Allow configuring and getting properties by name. Allow get for just one interface.

Netlink documentation is pretty bad. Useful resources: [blog post](http://maz-programmersdiary.blogspot.co.uk/2011/09/netlink-sockets.html)

Make commands that look more like `ip`, or as methods of the interface objects, or both. Currently adding metamethods, eg setflags.


