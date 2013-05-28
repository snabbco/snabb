# Unix system calls for LuaJIT

What? An FFI implementation of the Linux kernel ABI for LuaJIT. This means you will be able to program all the functionality the Linux kernel provides to userspace directly in Lua. You can view it as a high level language equivalent of the busybox project in a way, although the functionality it provides is somewhat different, and the interface very different.

Why? Making a C library for everything you want to bind is a pain, so I thought I would see what you could do without, and I want to do some low level system stuff in Lua. Use it if you want a comprehensive and tested set of easy to use bindings for LuaJIT, if you want to use Linux features without writing lots of C code riddled with macros, to learn about how operating systems work, as a configuration language or many other uses.

There is a work in progress port to BSD systems, currently targetting NetBSD (32 bit) and OSX (64 bit). These are currently less complete than the Linux version.

This code is beta. Interfaces will change in future. The code is riddled with TODOs. On the other hand it does work, and the changes at this stage will be smaller than in the past.

## Install

You just need to put the ```.lua``` files somewhere that LuaJIT will find them, eg typically in ```/usr/local/share/lua/5.1/```. Keep the directory structure there is. You can safely remove files from architectures and operating systems you do not use.

You can install using ```luarocks install rockspec/ljsyscall-scm-1.rockspec``` or one of the other versions in that directory, which will pull the version from github and install in the right place.

## Requirements

Requirements: Needs [LuaJIT 2.0.0](http://www.luajit.org/) or later.

The code does not currently support the main Lua implementation, only LuaJIT. It used to support [luaffi](https://github.com/jmckaskill/luaffi) but this has not kept up with LuaJIT ffi features. At some point I intend to support Lua directly, but this will be after the API has stabilised.

On Linux ARM (soft or hard float), x86, AMD64 and PPC architectures are supported; intend to support MIPS in future but currently my only MIPS hardwrae does not support LuaJIT. Either glibc/eglibc, [Musl libc](http://www.musl-libc.org/) or uClibc should work on Linux. Note that uClibc has had less testing, and it has a lot of configuration options. For full testing (as root) a recent kernel is recommended, eg Linux 3.5 or Ubuntu 12.04 is fine, as we use many recent features such as network namespaces to test thoroughly.

Android (ARM tested so far) currently passes some tests and fails others, so needs some more work, probably dealing with things that are not implemented in the kernel and other environment differences.

For the BSD support, testing is currently limited to NetBSD x86 32 bit (LuaJIT does not run on x64 at present due to lack of MAP_32BIT). NetBSD on ARM and PPC should work as it is clean and portable, and MIPS if LuaJIT runs. I am not currently supporting other BSDs (eg FreeBSD); it should not be difficult but there is an issue of how to detect which one is being used in order to deal with the (small) differences.

OSX support is tested on x64 and x86. In principle there should be no issues running it on ARM (ie iOS), but I have not had a chance to try yet, so there may be some other differences.

There will not be Windows support (although in principle Cygwin and similar platforms could be supported). If you want to do similar things on Windows you should try [TINN](https://github.com/Wiladams/TINN).

For the rump kernel functionality, the easiest way at present to install it is usually using the [buildrump.sh](https://github.com/anttikantee/buildrump.sh) project. Then install the libraries somewhere in your library path. The rump kernel is a way of [running parts of the NetBSD kernel in userspace as libraries](http://www.netbsd.org/docs/rump/). At the moment support is partially implemented, planning to add more soon, in particular to be able to script the backend "hypervisor" part. There will be full tests soon, but there is a basic example in `examples/rump` which is a port of one of the tests in buildrump.

## New features planned soon
netfilter, dhcp, selinux, arp, rump kernel backend, further BSD and OSX work.

## Release notes
0.7 bug fixes, general cleanups, filesystem capabilities, xattr bug fixes, signal handler functions, cpu affinity support, scheduler functions, POSIX message queues, tun/tap support, ioctl additions and improvements, initial NetBSD and OSX support, initial NetBSD rump kernel support, some fixes to allow Android to work.

0.6 adds support for raw sockets, BPF, seccomp mode 2 (syscall filtering), capabilities, feature tests, plus bug fixes.

0.5 adds support for ppc, has some bug fixes for 64 bit file handling on 32 bit architectures, and better organisation of files.

0.4 is a release that works well with LuaJIT 2.0.0 and has had extensive testing. The code is somewhat modular now, which makes it easier to use and understand.

0.3 was the last release to work with luaffi. There are significant bugs.

0.2 work in progress release.

0.1 very early prototype.

## Examples and documentation

Apart from the tests, there are now some examples at in the examples directory; more to come. There will be documentation before the 1.0 release, trying to work out the best way to incorporate it.

## Testing

[![Build Status](https://travis-ci.org/justincormack/ljsyscall.png)](https://travis-ci.org/justincormack/ljsyscall)

The test script is fairly comprehensive. Tested on ARM, amd64, x86, with various combinations of libc. I run long test runs as LuaJIT makes random choices in code generation so single runs do not necessarily show errors. Also tested with Valgrind to pick up memory errors, although there are some issues with some of the system calls, which are being gradually resolved (I use Valgrind SVN).

Some tests need to be run as root, and will not be run otherwise. You cannot test a lot of system calls otherwise. Under Linux the testing is now done in isolated containers so should not affect the host system, although on old kernels reboot in a container could reboot the host.

Some tests may fail if you do not have kernel support for some feature (eg namespacing, ipv6, bridges). Starting to add feature testing to work around this, but the way this works needs improving.

The test script is a copy of [luaunit](https://github.com/rjpcomputing/luaunit). I have pushed all my changes upstream, including Lua 5.2 support and fixes to not allocate globals.

I have added initial coverage tests (now need fixing), and a C test to check constants and structures. The C test is useful for picking up errors but needs a comprehensive set of headers which eg is not available on most ARM machines so it can be difficult to run. I am putting together a set of hardware to run comprehensive tests on to make this less of an issue.

There is now [Travis CI](https://travis-ci.org/) support, although this will only test on one architecture (x86, glibc) at present (looks like OSX support may come soon). You can [see the test results here](https://travis-ci.org/justincormack/ljsyscall). If you fork the code you should be able to run these tests by setting up your own Travis account, and they will also be run for pull requests.

## What is implemented?

This project is in beta! Much stuff is still missing, this is a work in progress! The majority of syscalls are now there, let me know if you need some that are not.

As well as syscalls, there are interfaces to features such as proc, termios and netlink. These are still work in progress, and will be split into separate modules.

Work on the netlink API is progressing. You can now do `print(S.get_interfaces()` to get something much like ifconfig returns, and all the raw data is there as Lua tables. You can then modify these, and add IP addresses, similarly for routes. There is also a raw netlink interface, and you can create new interfaces. There is a lot more functionality that netlink needs to provide, but this is now mostly a matter of configuration. The API needs more work still. Netlink documentation is pretty bad. Useful resources: [blog post](http://maz-programmersdiary.blogspot.co.uk/2011/09/netlink-sockets.html)

There is also a lot of the `ioctl` interfaces to implement, which are very miscellaneous. Mostly you just need some constants and typecasting, but helper functions are probably useful.

The aim is to provide nice to use, Lua friendly interfaces where possible, but more work needs to be done, as have really started with the raw interfaces, but adding functionality through metatypes. Where possible the aim is to provide cross platform interfaces for higher level functionality that are as close as possible at least in a duck-typing sort of way.

## Note on libc

Lots of system calls have glibc wrappers, some of these are trivial some less so, and some are broken. In particular some of them expose different ABIs, so we try to avoid these, just using kernel ABIs as these have long term support and we are not trying to be compatible as we are using a different language. `strace` is your friend, although strace is buggy in the nasty edge cases (at some point ljsyscall will implement ptrace so it can debug itself).

As well as eglibc and glibc, everything now runs on [Musl libc](http://www.etalabs.net/musl/). I use [sabotage](https://github.com/rofl0r/sabotage) as a build environment, which now includes luajit, although you may need to update to git head. Musl is much smaller than libc (700k vs 3M), while still implementing everything we need in easy to understand code. It is also MIT licensed, which may be useful as it matches the other licenses for LuaJIT and ljsyscall. Occasionally I find small bugs and missing features which I feed back to the developers.

### API

All functions return two values, the return value, or true if there is not one other than success, then an error value. This makes it easy to write things like `assert(fd:close())`. The error type can be converted to a string message, or you can retrieve the errno, or test against a symbolic error name.

File descriptors are returned as a type not an integer. This is because they are garbage collected by default, ie if they go out of scope the file is closed. You can get the file descriptor using the fileno field. To disable the garbage collection you can call `fd:nogc()`, in which case you need to close the descriptors by hand. They also have methods for operations that take an fd, like `close`, `fsync`, `read`. You can use this type where an fd is required, or a numeric fd, or a string like "stderr".

String conversions are not done automatically, you get a buffer back, you have to force a conversion. This is because interning strings is expensive if you do not need it. However if you do not supply a buffer for the return value, you will get a string in general as more useful.

Many functions that return structs return metatypes exposing additional methods, so you get the raw values eg `st_size` and a Lua number as `size`, and possibly some extra helpful methods. As these are (ffi) metamethods they have no overhead, so more can be added to make the interfaces easier to use.

Constants should all be available, eg `c.SEEK.SET` etc, note they are namespaced into Lua tables rather than underscore seperated like in C. The constant tables will also let you combine flags where appropriate and you can use lower case, so `c.O["rdonly, create"]` is the same as the bitwise or of `c.O.RDONLY` and `c.O.CREAT`. When you call a function, you can just pass the string, as `fd = S.open("file", "rdonly, creat")` which makes things much more concise.

You do not generally need to use the numbered versions of functions, eg dup can do dup2 or dup3 by adding more arguments (not fully consistent yet).

Types are key, as these encapsulate a lot of functionality, and easy to use constructors and helpful methods. For example you can create the `in_addr` type with `addr = t.in_addr("127.0.0.1")` or `addr = t.in_addr("loopback")`.

The test cases are good examples until there is better documentation!

A very few functions have arguments in a different order to make optional ones easier. This is a bit confusing sometimes, so check the examples or source code.

It would be nice to be API compatible with other projects, especially Luaposix, luasocket, nixio. Unfortunately none of these seem to have good test suites, and there interfaces are problematic for some functions, so this has been put on hold.

### Performance

If you want the highest performance, allocate and pass your own buffers, as obviously allocation is expensive. It is now fine to use the string flags for functions, as these are memoized. Check the output of `luajit -jv` to see what is going on and let me know if there are any issues that need fixes for NYI functions. You should be able to get native C like performance.

There is an example epoll script that you can test with Apachebench in the examples directory. On my machine apachebench uses more CPU time than the script so the results are a bit low.

### Issues

There will no doubt be bugs and missing features, please report them if you find them. Also API design issues. You can use the [github issue tracker](https://github.com/justincormack/ljsyscall/issues?page=1&state=open).


