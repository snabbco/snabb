# Unix system calls for LuaJIT

[![Build Status](https://travis-ci.org/justincormack/ljsyscall.png)](https://travis-ci.org/justincormack/ljsyscall)

What? An FFI implementation of the Linux and NetBSD kernel ABIs for LuaJIT. This means you will be able to program all the functionality the Linux kernel provides to userspace directly in Lua. You can view it as a high level language equivalent of the busybox project in a way, although the functionality it provides is somewhat different, and the interface very different.

Why? First it provides a comprehensive set of system call APIs for programming sockets, files and so on, including the more obscure things (eg file change notifications). Second it provides higher level interfaces such as network interface configuration, so your application can control its entire runtime interface including IP addresses routing and so on. Third it provides tools for added security, such as support for Linux namespaces (containers), system call filtering (seccomp type 2), capabilities and so on, all with a script language interface that is much simpler to use than the C interface. As it is Lua based it can easily be embedded in another language; in the future ports to other scripting languages are planned. It also serves as a way of learning how the operating system interfaces work in a more forgiving environment than C.

There is a work in progress port to BSD systems, currently targetting NetBSD. NetBSD support is now relatively good and working towards parity with Linux. This also works with the NetBSD rump kernel under other operating systems and natively without an operating system under Xen - see https://github.com/justincormack/rumpuser-xen for details.

This code is beta. Interfaces will change in future. The code is riddled with TODOs. On the other hand it does work, and the changes at this stage will be smaller than in the past.

## Introductory talk

There is the [video of my FOSDEM 2013 talk](http://www.myriabit.com/ljsyscall/) here.

## Install

For simple uses, you just need to put the ```.lua``` files somewhere that LuaJIT will find them, eg typically in ```/usr/local/share/lua/5.1/```. Keep the directory structure there is. You can safely remove files from architectures and operating systems you do not use.

If you are using Lua rather than LuaJIT you need to install [luaffi](https://github.com/jmckaskill/luaffi) first.

There is more information in the INSTALL file.

## Requirements

Requirements: Needs [LuaJIT 2.0.2](http://www.luajit.org/) or later.

The code does not currently portably support the main Lua implementation, only LuaJIT. It now runs again with [luaffi](https://github.com/jmckaskill/luaffi) under standard Lua 5.2 (and probably 5.1, untested). Because the function calls in luaffi use dynasm they are not fully portable, so I will be adding support for Lua C interface function calls as well shortly. This is not yet integrated into the test suite.

On Linux ARM (soft or hard float), x86, AMD64 and PPC architectures are supported; MIPS support will be completed soon. Either glibc/eglibc, [Musl libc](http://www.musl-libc.org/) or uClibc should work on Linux. Note that uClibc has had little testing. For full testing (as root) a recent kernel is recommended, eg Linux 3.5 or Ubuntu 12.04 is fine, as we use many recent features such as network namespaces to test thoroughly.

Android (ARM tested so far) currently passes all the non root tests now; some tests are be skipped as the kernel does not ship with some functionality (aio, mq). Generally much functionality is available even though it is not in Bionic libc.

For the NetBSD support all platforms should work in principle; more test targets will be added soon, currently tests being run on x86 and amd64, an ARM test target will be added soon.

There is a small stub of FreeBSD support, not yet enough to run any code (although rump works on FreeBSD). A small amount of OSX support was added but there is no test environment at present.

There will not be Windows support (although in principle Cygwin and similar platforms could be supported). If you want to do similar things on Windows you should try [TINN](https://github.com/Wiladams/TINN).

For the (optional) rump kernel functionality, the easiest way at present to install it is usually using the [buildrump.sh](https://github.com/anttikantee/buildrump.sh) project, which is now included as a git submodule. The rump kernel is a way of [running parts of the NetBSD kernel in userspace as libraries](http://www.netbsd.org/docs/rump/). At the moment support is partially implemented, planning to add more soon, in particular to be able to script the backend "hypervisor" part. There are some additional examples in `examples/rump` which is a port of the tests in buildrump. The rump kernel runs on many elf/Posix OS and architectures, currently tested on Linux x86, x64, ppc, arm and NetBSD x86, x64, with more targets to be added soon.

## New features planned soon
netfilter, dhcp, selinux, arp, better sockopt handling, cgroups support, more NetBSD support, rump kernel hypercall API, OSv support, Lua support, more introspection, FreeBSD support.

## Release notes
0.9pre bug fixes, better tests, reworking of how methods are called, more NetBSD support, termios interface rework, improved ioctl that understands type and direction of arguments, more NetBSD network config, rump kernel Linux ABI support, cleanups, full ppc support, endian fixes, Android fixes, Xen support, kqueue, poll and epoll interface improvements, additional syscalls, luaffi support again, better kernel headers and fixes against them, more MIPS support, improved APIs with multiple return values, initial NetBSD and Rump ktrace support.

0.8 rump kernel fixes, NetBSD 64 bit fixes, initial arp/neighbour support, towards MIPS support, cmsg cleanup, shm_open, iterators for directory iteration and ls, more OSX and NetBSD support, initial cgroups support, initial support of NetBSD network config.

0.7 bug fixes, general cleanups, filesystem capabilities, xattr bug fixes, signal handler functions, cpu affinity support, scheduler functions, POSIX message queues, tun/tap support, ioctl additions and improvements, initial NetBSD and OSX support, initial NetBSD rump kernel support, some fixes to allow Android to work.

0.6 adds support for raw sockets, BPF, seccomp mode 2 (syscall filtering), capabilities, feature tests, plus bug fixes.

0.5 adds support for ppc, has some bug fixes for 64 bit file handling on 32 bit architectures, and better organisation of files.

0.4 is a release that works well with LuaJIT 2.0.0 and has had extensive testing. The code is somewhat modular now, which makes it easier to use and understand.

0.3 was the last release to work with luaffi. There are significant bugs.

0.2 work in progress release.

0.1 very early prototype.

## Examples and documentation

Apart from the tests, there are now some examples at in the examples directory; more to come.

There will be proper documentation before the 1.0 release, apologies for it not being available sooner. I understand how important it is and it is planned shortly.

## Testing

The test script is fairly comprehensive. Tested on ARM, amd64, x86, with various combinations of libc. I run long test runs as LuaJIT makes random choices in code generation so single runs do not necessarily show errors. Also tested with Valgrind to pick up memory errors, although there are some issues with some of the system calls, which are being gradually resolved (I use Valgrind SVN).

Some tests need to be run as root, and will not be run otherwise. You cannot test a lot of system calls otherwise. Under Linux the testing is now done in isolated containers so should not affect the host system, although on old kernels reboot in a container could reboot the host.

Some tests may fail if you do not have kernel support for some feature (eg namespacing, ipv6, bridges). Starting to add feature testing to work around this, but the way this works needs improving.

The test script is a copy of [luaunit](https://github.com/rjpcomputing/luaunit). I have pushed all my changes upstream, including Lua 5.2 support and fixes to not allocate globals.

I have added initial coverage tests (now need fixing), and a C test to check constants and structures. The C test is useful for picking up errors but needs a comprehensive set of headers which eg is not available on most ARM machines so it can be difficult to run. I am putting together a set of hardware to run comprehensive tests on to make this less of an issue.

There is now [Travis CI](https://travis-ci.org/) support, although this will only test on one architecture (x64, glibc) at present. You can [see the test results here](https://travis-ci.org/justincormack/ljsyscall). If you fork the code you should be able to run these tests by setting up your own Travis account, and they will also be run for pull requests.

I have used the LuaJIT [reflect library](http://www.corsix.org/lua/reflect/api.html) for checking struct offsets.

Adding buildbot tests for a wider variety of architectures, as Travis is limited to Linux/Ubuntu. Currently building on Linux ARM, PowerPC, x64 and x86 and NetBSD x86 and x64, more targets to come soon. The [buildbot dashboard is now up](http://build.myriabit.eu:8010/).

## What is implemented?

This project is in beta! Much stuff is still missing, this is a work in progress! The majority of syscalls are now there, let me know if you need some that are not.

As well as syscalls, there are interfaces to features such as proc, termios and netlink. These are still work in progress, and are being split into separate modules.

Work on the Linux netlink API is progressing. You can now do `print(S.get_interfaces()` to get something much like ifconfig returns, and all the raw data is there as Lua tables. You can then modify these, and add IP addresses, similarly for routes. There is also a raw netlink interface, and you can create new interfaces. There is a lot more functionality that netlink needs to provide, but this is now mostly a matter of configuration. The API needs more work still. Netlink documentation is pretty bad. Useful resources: [blog post](http://maz-programmersdiary.blogspot.co.uk/2011/09/netlink-sockets.html)

There is also a lot of the `ioctl`, `getsockopt` and `fcntl` interfaces to implement, which are very miscellaneous. Mostly you just need some constants and typecasting, but helper functions are probably useful. These are being improved so they understand the underlying types and functionality, making them less error prone.

The aim is to provide nice to use, Lua friendly interfaces where possible, but more work needs to be done, as have really started with the raw interfaces, but adding functionality through metatypes. Where possible the aim is to provide cross platform interfaces for higher level functionality that are as close as possible at least in a duck-typing sort of way.

## Note on libc

Under Linux, lots of system calls have glibc wrappers, some of these are trivial some less so, and some are broken. In particular some of them expose different ABIs, so we try to avoid these, just using kernel ABIs as these have long term support and we are not trying to be compatible as we are using a different language. `strace` is your friend, although strace is buggy in the nasty edge cases (at some point ljsyscall will implement ptrace so it can debug itself). Therefore under Linux the project is gradually moving to calling system calls directly, bypassing the libc, just keeping directly to the kernel ABI.

As well as eglibc and glibc, everything now runs on [Musl libc](http://www.etalabs.net/musl/). I use [sabotage](https://github.com/rofl0r/sabotage) as a build environment, which now includes luajit, although you may need to update to git head. Musl is much smaller than libc (700k vs 3M), while still implementing everything we need in easy to understand code. It is also MIT licensed, which may be useful as it matches the other licenses for LuaJIT and ljsyscall. Occasionally I find small bugs and missing features which I feed back to the developers. The Android libc, bionic, is also supported now, mainly by bypassing it and calling the system calls directly.

Under NetBSD it is much simpler, the only thing we need to be careful of is versioned systemm calls in libc, where we directly call a specific version as the plain name will always refer to the old version for compatibility.

### API

This will be documented properly soon, once it stabilises.

All functions return two or more values, the return value, or true if there is not one other than success, then an error value. This makes it easy to write things like `assert(fd:close())`. The error type can be converted to a string message, or you can retrieve the errno, or test against a symbolic error name. Some functions then return additional return values, such as `pipe()` that returns the two file descriptors for the pipe. A few functions return a Lua iterator, such as `epoll_wait()`.

File descriptors are returned as a type not an integer. This is because they are garbage collected by default, ie if they go out of scope the file is closed. You can get the file descriptor using the fileno field. To disable the garbage collection you can call `fd:nogc()`, in which case you need to close the descriptors by hand. They also have methods for operations that take an fd, like `close`, `fsync`, `read`. You can use this type where an fd is required, or a numeric fd, or a string like "stderr".

String conversions are not done automatically, you get a buffer back, you have to force a conversion. This is because interning strings is expensive if you do not need it. However if you do not supply a buffer for the return value, you will get a string in general as more useful.

Many functions that return structs return metatypes exposing additional methods, so you get the raw values eg `st_size` and a Lua number as `size`, and possibly some extra helpful methods. As these are (ffi) metamethods they have no overhead, so more can be added to make the interfaces easier to use.

Where there are variable length arrays, these are bundled together into a structure that has an array and a count, so you do not need to keep passing around the size. These provide iterators, which helps hide the fact that they are 0-based.

Constants should all be available, eg `c.SEEK.SET` etc, note they are namespaced into Lua tables rather than underscore seperated like in C. The constant tables will also let you combine flags where appropriate and you can use lower case, so `c.O["rdonly, create"]` is the same as the bitwise or of `c.O.RDONLY` and `c.O.CREAT`. When you call a function, you can just pass the string, as `fd = S.open("file", "rdonly, creat")` which makes things much more concise.

You do not generally need to use the numbered versions of functions, eg dup can do dup2 or dup3 by adding more arguments (not fully consistent yet).

Types are key, as these encapsulate a lot of functionality, and easy to use constructors and helpful methods. For example you can create the `in_addr` type with `addr = t.in_addr("127.0.0.1")` or `addr = t.in_addr("loopback")`.

The test cases are good examples until there is better documentation!

A very few functions have arguments in a different order to make optional ones easier. This is a bit confusing sometimes, so check the examples or source code.

It would be nice to be API compatible with other projects, especially Luaposix, luasocket, nixio. Unfortunately none of these seem to have good test suites, and there interfaces are problematic for some functions, so this has been put on hold, although basic luasocket support is planned fairly soon.

### Performance

If you want the highest performance, allocate and pass your own buffers, as obviously allocation is expensive. It is now fine to use the string flags for functions, as these are memoized. Check the output of `luajit -jv` to see what is going on and let me know if there are any issues that need fixes for NYI functions. You should be able to get native C like performance.

There is an example epoll script that you can test with Apachebench in the examples directory. On my machine apachebench uses more CPU time than the script so the results are a bit low.

### Porting

If you wish to port to an unsupported platform, please get in touch for help. All contributions welcomed.

Porting to different Linux processor architectures is a matter of filling in the constants and types that differ. The `ctest` tests will flag issues with these, although many platforms are also missing headers which makes it more complex. If you can provide qemu target information that would be helpful as the platform can be added to the test suite.

Porting to different OSs is a fair amount of work, but can generally be done gradually. The other BSDs should be very similar to NetBSD and OSX. Solaris has an ABI defined by libc not the kernel ABI, which would mean that you should probably target that. The first thing to do is check the base shared types, and work out if there are issues with large file support if it is a 32 bit platform. There are more sharing opportunities between OSs that should be dealt with, at the moment for example there is some repetition with OSX and NetBSD, so some restructuring would be helpful. 

If you want to port this to a different language, then get in touch, as I have some ideas and plans along this route, though I am trying to get a good fairly stable interface in Lua first. Pypy and Ruby ought to be suitable targets as they have an ffi; I also intend to do a classic Lua port using the C API. I intend to use reflection to generate more generic data for the ports, and rework how files are included. The first thing to do is just prototype some basic functions to see what is needed. Get in touch if you are interested in a port!

### Issues

There will no doubt be bugs and missing features, please report them if you find them. Also API design issues. You can use the [github issue tracker](https://github.com/justincormack/ljsyscall/issues?page=1&state=open) to report issues.

### License

All the ljsyscall code is under the MIT license. The ABI definitions are considered to be non copyrighted or CC0 if you need an official disclaimer. See LICENSE file for further details.



