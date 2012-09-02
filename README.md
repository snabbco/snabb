# Linux system calls for LuaJIT

What? An FFI implementation of the Linux kernel ABI for LuaJIT.

Why? Making a C library for everything you want to bind is a pain, so I thought I would see what you could do without, and I want to do some low level system stuff in Lua.

Linux only? Not so easy to port to other Unixes, you need to check the types and constants are correct, and remove anything that is not in your C library (that applies also to any non glibc library too), and test. Patches accepted, but will probably need to restructure for maintainability. However you may well be better off using [LuaPosix](https://github.com/rrthomas/luaposix) if you want to write portable Unix code.

Requirements: Needs LuaJIT 2.0.0-beta10 or later. Generally tested using git head. Currently requires git head.

Also supports [luaffi](https://github.com/jmckaskill/luaffi) so you can use with standard Lua; all the tests now pass, have added some workarounds to support current issues in luaffi which could be removed but these are not performance critical or important now as all the major issues have been resolved. There may still be a few issues in code that is not exercised by the tests, but actually luaffi has fixed most of the issues that were coming up anyway now. This is now tested and working with Lua 5.1 and 5.2.

Releases after tag 0.3 do not currently work with luaffi, please use that until fixed. Using new ffi features to simplify code.

## Examples

Apart from the tests, there are now some examples at [ljsyscall-examples](https://github.com/justincormack/ljsyscall-examples). More to come.

## Testing

The test script is quite comprehensive, though it does not test all the syscalls, as I assume they work, but it should stress the bindings. Tested on ARM, amd64, x86. Intend to get my ppc build machine back up one day, if you want this supported please ask. I do not currently have a mips box, if you want this can you suggest a suitable dev box.

Some tests need to be run as root, and will not be run otherwise. You cannot test a lot of stuff otherwise. However most of the testing is now done in isolated containers so should be harmless.

Some tests may fail if you do not have kernel support for some feature (eg namespacing, ipv6, etc).

Initial testing on uclibc, at one point worked on my configuration, but uclibc warns that ABI can depend on compile options, so please test. I thought uclibc used kernel structures for eg stat, but they seem to use the glibc ones now, so more compatible. If there are more compatibility issues I may move towards using more syscalls directly, now we have the syscall function. Other C libraries may need more changes; I intend to test musl libc once I have a working build.

The test script is a copy of [luaunit](https://github.com/rjpcomputing/luaunit). I have pushed all my changes upstream, including Lua 5.2 support and fixes to not allocate globals.

I have added initial coverage tests, which are over 90% (some functions may be missing, will update). Fixing the missing parts gradually (found some bugs from this).

## What is implemented?

This project is in beta! Some syscalls are missing, this is a work in progress! The majority of syscalls are now there, let me know if you need some that are not.

The syscall API covers a lot of stuff, but there are other interfaces. There is now a small wrapper for the process interface (/proc).

Work on the netlink API is progressing. A lot of the code for bridges was done as a prototype, and now working on the interface for network interfaces. The read side of network interfaces is done, you can now do `print(S.get_interfaces()` to get something much like ifconfig returns, and all the raw data is there as Lua tables. Still to do are the write side of these interfaces, and the additional parts such as routing, but these should be quicker to implement now some is done, although these interfaces are quite large.

There is also a lot of the `ioctl` interfaces to implement, which are very miscellaneous. Mostly you just need some constants and typecasting, but helper functions are probably useful.

The termios and pty interfaces have been implemented, thanks to [bdowning](https://github.com/bdowning). These wrap the libc calls, which underneath are mostly `ioctl` interfaces plus interfaces to the `/dev/pty` devices.

The aim is to provide nice to use, Lua friendly interfaces where possible, but more work needs to be done, as have really started with the raw interfaces, but adding functionality through metatypes.

## Note on libc

Lots of system calls have glibc wrappers, some of these are trivial some less so, and some are broken. In particular some of them expose different ABIs, so we try to avoid these, just using kernel ABIs as these have long term support and we are not trying to be compatible as we are using a different language. `strace` is your friend.

As well as eglibc and glibc, everything now runs on [Musl libc](http://www.etalabs.net/musl/). I use [sabotage](https://github.com/rofl0r/sabotage) as a build environment, which now includes luajit, although you may need to update to git head. Musl is much smaller than libc (700k vs 3M), while still implementing everything we need in easy to understand code. It is also BSD licensed, which may be useful as it matches the other licenses for LuaJIT and ljsyscall.

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

inet, inet6, unix, netlink.

### API

All functions return two values, the return value, or true if there is not one other than success, then an error value. This makes it easy to write things like assert(fd:close()). The error type can be converted to a string message, or you can retrieve the errno, or test against a symbolic error name.

File descriptors are returned as a type not an integer. This is because they are garbage collected by default, ie if they go out of scope the file is closed. You can get the file descriptor using the fileno field. To disable the garbage collection you can call fd:nogc(), in which case you need to close the descriptors by hand. They also have methods for operations that take an fd, like close, fsync, read. You can use this type where an fd is required, or a numeric fd, or a string like "stderr". 

String conversions are not done automatically, you get a buffer back, you have to force a conversion. This is because interning strings is expensive if you do not need it. However if you do not supply a buffer for the return value, you will get a string in general as more useful.

Many functions that return structs return metatypes exposing additional methods, so you get the raw values eg `st_size` and a Lua number as `size`, and possibly some extra helpful methods, like `major` and `minor` from stat. As these are metamethods they have no overhead, so more can be added to make the interfaces easier to use.

Constants should all be available, eg `L.SEEK_SET` etc. You can add to combine them. They are also available as strings, so "SEEK\_SET" will be converted to S.SEEK\_SET. You can miss off the "SEEK\_" prefix, and they are not case sensitive, so you can just use `fd:lseek(offset, "set")` for more concise and readable use. If multiple flags are allowed, they can be comma separated for logical OR, such as `S.mmap(nil, size, "read", "private, anonymous", -1, 0)`. Note that there is some namespacing overlap, so some invalid flags can be used. Perhaps we should define shorter sets as a table when this could happen.

You do not need to use the numbered versions of functions, eg dup can do dup2 or dup3 by adding more arguments

Standard convenience macros are also provided, eg S.major(dev) to extract a major number from a device number. Generally metamethods are also provided for these.

`bind` does not require a length for the address type length, as it can work this out dynamically.

`uname` returns a Lua table with the returned strings in it. Similarly `getdents` returns directory entries as a table. Other functions such as `poll` return an ffi metatype that behaves like a Lua array, ie is 1-indexed and has a `#` length method, which wraps the underlying C structure.

The test cases are good examples until I do better documentation!

A few functions have arguments in a different order to make optional ones easier. This is a bit confusing sometimes, so check the examples or source code.

It would be nice to be API compatible with other projects, especially Luaposix, luasocket, nixio. I should have probably looked at these before I started, but things can be changed. Startde some nixio compatibility, in progress.

### Performance

If you want the highest performance, allocate and pass your own buffers, as obviously allocation is expensive. It is now fine to use the string flags for functions, as these are memoized. Check the output of `luajit -jv` to see what is going on and let me know if there are any issues that need fixes for NYI functions. You should be able to get native C like performance.

There is an example epoll script that you can test with Apachebench (in the examples)[https://github.com/justincormack/ljsyscall-examples]. On my machine apachebench uses more CPU time than the script so the results are a bit low.

### Issues

Siginfo support in sigaction not there yet, as confused by the kernel API.

only some of aio is working, needs some debugging before being used. Also all the iocb functions should be replaced with metatypes eg getiocb, getiocbs.

There will no doubt be bugs, please report them if you find them.

### Missing functions etc

pselect, ppoll
timer\_create, timer\_getoverrun, clock_adjtime
sigqueue,
capset, capget
pivot\_root, init\_module, delete\_module, query\_module, get_\kernel\_syms, swapon, swapoff
iopl, ioperm
futex, set\_robust\_list, get\_robust\_list
getrusage, ptrace
setfsuid, setfsgid
setpgid, getpgid, setpgrp, getpgrp
recvmmsg
mq\_open, mq\_close, mq\_getattr, mq\_notify, mq\_receive, mq\_send, mq\_unlink -- note glibc wraps these
quotactl, ioprio\_set, ioprio\_get
setdomainname, bdflush, kexec\_load
mbind, get\_mpolicy, set\_mpolicy
sysfs, mincore, remap\_file\_pages, set\_tid\_address
add\_key, request\_key, keyctl (see libkeyutils wrappers)
sched\_setaffinity, sched\_getaffinity, migrate\_pages, move\_pages
perf\_event\_open  -- see http://web.eecs.utk.edu/~vweaver1/projects/perf-events/programming.html
set\_thread\_area, get\_thread\_area, exit_group, tgkill
open\_by\_handle\_at, name\_by\_handle\_at
...

note we will probably implement the posix ipc not sysv, as functionality slightly better.
sys v ipc: msgctl, msgget, msgrcv, msgsnd, semctl, semget, semop, semtimedop, shmat, shmctl, shmdt, shmget

probably not useful: brk, uselib, socketcall, idle, ipc, modify_ldt, personality, sigreturn, sigaltstack, lookup\_dcookie

from man(3)
clock_getcpuclockid
getdomainname (from uname)
ftok
shm_open and other posix functions (use /dev/shm)
uuid

### 64 bit fileops on 32 bit

These now work and have tests, the 64 bit operations are always used on 32 bit architectures.

Note that fcntl64 has not been changed yet, as we have not defined the flock structure which is the change, and it is wrapped by glibc. statfs is also wrapped by glibc.

### uid size.
Linux 2.4 increased the size of user and group IDs from 16 to 32 bits.  Tosupport this change, a range of system calls were added (e.g., chown32(2),getuid32(2), getgroups32(2), setresuid32(2)), superseding earlier calls ofthe same name without the "32" suffix.

The glibc wrappers hide this, and call the 32 bit calls anyway, so should be ok.

## netlink
Allow configuring and getting properties by name. Allow get for just one interface.

Netlink documentation is pretty bad. Useful resources: [blog post](http://maz-programmersdiary.blogspot.co.uk/2011/09/netlink-sockets.html)

Make commands that look more like `ip`, or as methods of the interface objects, or both. Currently adding metamethods, eg setflags.

Currently support get, add and delete for interfaces, routes and addresses, although functionality not fully complete even for these, and API not finalized.

## nixio compatibility

Current plan is to have the same level of functionality, but not worry about except compatibility for now. I can't find a test suite, and the API choice does not seem very well thought out.

## TODO

Misc list of ideas, no particular order

1. non blocking netlink functions ie return EAGAIN but can resume.
2. futex support. Needs some assembly support.
3. Other atomic ops eg CAS - see https://lwn.net/Articles/509102/
4. try using llvm to parse headers to get syscall numbers, or a C program. Generate headers by arch.
5. evented coroutine example
6. iterators eg for reading large files? (cat)
7. ping support
8. dhcp client
9. misc shell commands eg touch
10. syslog? Not sure. Might do remote protocol.
11. selinux
12. seccomp
13. insmod, lsmod, depmod
14. decide on netlink interface, still experimenting
15. netlink missing functionality and tests
16. use netlink instead of bridge ioctls for create, destroy.
17. sysctl wrapper (trivial write to /proc/sys)
18. cgroups
19. replace more of the man(3) stuff with native syscalls. More transparent.
20. Standard lua support, eventually. Might start with luasocket support for netlink, but there is a lot of work to do.
21. make more modular, started with netlink and arch specific but needs more.
22. udev (uses netlink)
23. netlink listen for events
24. fix fs specific mount ops so can round-trip mounts
25. fix aio
26. automate ctest.lua to do full compile and run

