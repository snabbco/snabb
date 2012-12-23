# Linux system calls for LuaJIT

What? An FFI implementation of the Linux kernel ABI for LuaJIT. This means you will be able to program all the functionality the Linux kernel provides to userspace directly in Lua. You can view it as a high level language equivalent of the busybox project in a way, although the functionality it provides is somewhat different, and the interface very different.

Why? Making a C library for everything you want to bind is a pain, so I thought I would see what you could do without, and I want to do some low level system stuff in Lua.

Linux only? Not so easy to port to other Unixes, you need to check the types and constants are correct, and remove anything that is not in your C library, and test. Patches accepted, but will probably need to restructure for maintainability. Other Unixes may not provide the same ABI stability guarantees, from the kernel, they will usually provide from libc instead, as these are often tightly coupled. However you may well be better off using [LuaPosix](https://github.com/rrthomas/luaposix) if you want to write portable Unix code.

Requirements: Needs [LuaJIT 2.0.0](http://www.luajit.org/) or later.

The code does not currently support the main Lua implementation, only LuaJIT. It used to support [luaffi](https://github.com/jmckaskill/luaffi) but this has not kept up with LuaJIT ffi features. At some point I intend to support Lua directly, but this will be after the API has stabilised.

This code is beta. Interfaces will change in future. The code is riddled with TODOs. On the other hand it does work, and the changes at this stage will be smaller than in the past.

## Requirements

LuaJIT 2.0.0 or later. ARM (soft or hard float), x86 or AMD64 architectures; intend to support PPC and MIPS in future. Either glibc or [Musl libc](http://www.musl-libc.org/) or uClibc should work. Note that uClibc has had less testing, and it has a lot of configuration options, in particular it will not work correctly without largefile support. For full testing (as root) a recent kernel is recommended, eg Linux 3.5 or Ubuntu 12.04 is fine, as we use many recent features such as network namespaces to test thoroughly.

## Release notes

0.4 is a release that works well with LuaJIT 2.0.0 and has had extensive testing. The code is somewhat modular now, which makes it easier to use and understand.

0.3 was the last release to work with luaffi. There are significant bugs.

0.2 work in progress release.

0.1 very early prototype.

## Examples

Apart from the tests, there are now some examples at [ljsyscall-examples](https://github.com/justincormack/ljsyscall-examples). More to come.

## Testing

The test script is fairly comprehensive. Tested on ARM, amd64, x86, with various combinations of libc. I run long test runs as LuaJIT makes random choices in code generation so single runs do not necessarily show errors. Also tested with Valgrind to pick up memory errors, although there are some issues with some of the system calls, which are being gradually resolved (I use Valgrind SVN).

Some tests need to be run as root, and will not be run otherwise. You cannot test a lot of system calls otherwise. The testing is now done in isolated containers so should not affect the host system, although on old kernels reboot in a container could reboot the host.

Some tests may fail if you do not have kernel support for some feature (eg namespacing, ipv6, bridges).

The test script is a copy of [luaunit](https://github.com/rjpcomputing/luaunit). I have pushed all my changes upstream, including Lua 5.2 support and fixes to not allocate globals.

I have added initial coverage tests, and a C test to check constants and structures, but these are very much work in progress.

There is now limited [Travis CI](https://travis-ci.org/) support, although this will only test on one architecture (x86, glibc). You can [see the test results here](https://travis-ci.org/justincormack/ljsyscall). If you fork the code you should be able to run these tests by setting up your own Travis account.

## What is implemented?

This project is in beta! Much stuff is still missing, this is a work in progress! The majority of syscalls are now there, let me know if you need some that are not.

As well as syscalls, there are interfaces to features such as proc, termios and netlink. These are still work in progress, and will be split into separate modules.

Work on the netlink API is progressing. You can now do `print(S.get_interfaces()` to get something much like ifconfig returns, and all the raw data is there as Lua tables. You can then modify these, and add IP addresses, similarly for routes. There is also a raw netlink interface, and you can create new interfaces. There is a lot more functionality that netlink needs to provide, but this is now mostly a matter of configuration. The API needs more work still. Netlink documentation is pretty bad. Useful resources: [blog post](http://maz-programmersdiary.blogspot.co.uk/2011/09/netlink-sockets.html)

There is also a lot of the `ioctl` interfaces to implement, which are very miscellaneous. Mostly you just need some constants and typecasting, but helper functions are probably useful.

The termios and pty interfaces have been implemented, thanks to [bdowning](https://github.com/bdowning). These wrap the libc calls, which underneath are mostly `ioctl` interfaces plus interfaces to the `/dev/pty` devices.

The aim is to provide nice to use, Lua friendly interfaces where possible, but more work needs to be done, as have really started with the raw interfaces, but adding functionality through metatypes.

## Note on libc

Lots of system calls have glibc wrappers, some of these are trivial some less so, and some are broken. In particular some of them expose different ABIs, so we try to avoid these, just using kernel ABIs as these have long term support and we are not trying to be compatible as we are using a different language. `strace` is your friend.

As well as eglibc and glibc, everything now runs on [Musl libc](http://www.etalabs.net/musl/). I use [sabotage](https://github.com/rofl0r/sabotage) as a build environment, which now includes luajit, although you may need to update to git head. Musl is much smaller than libc (700k vs 3M), while still implementing everything we need in easy to understand code. It is also BSD licensed, which may be useful as it matches the other licenses for LuaJIT and ljsyscall.

### API

All functions return two values, the return value, or true if there is not one other than success, then an error value. This makes it easy to write things like `assert(fd:close())`. The error type can be converted to a string message, or you can retrieve the errno, or test against a symbolic error name.

File descriptors are returned as a type not an integer. This is because they are garbage collected by default, ie if they go out of scope the file is closed. You can get the file descriptor using the fileno field. To disable the garbage collection you can call `fd:nogc()`, in which case you need to close the descriptors by hand. They also have methods for operations that take an fd, like `close`, `fsync`, `read`. You can use this type where an fd is required, or a numeric fd, or a string like "stderr".

String conversions are not done automatically, you get a buffer back, you have to force a conversion. This is because interning strings is expensive if you do not need it. However if you do not supply a buffer for the return value, you will get a string in general as more useful.

Many functions that return structs return metatypes exposing additional methods, so you get the raw values eg `st_size` and a Lua number as `size`, and possibly some extra helpful methods. As these are (ffi) metamethods they have no overhead, so more can be added to make the interfaces easier to use.

Constants should all be available, eg `c.SEEK.SET` etc. The constant tables will also let you combine flags where appropriate and you can use lower case, so `c.O["rdonly, create"]` is the same as the bitwise or of `c.O.RDONLY` and `c.O.CREAT`. When you call a function, you can just pass the string, as `fd = S.open("file", "rdonly, creat")` which makes things much more concise.

You do not generally need to use the numbered versions of functions, eg dup can do dup2 or dup3 by adding more arguments

Types are key, as these encapsulate a lot of functionality, and easy to use constructors and helpful methods. For example you can create the `in_addr` type with `addr = t.in_addr("127.0.0.1")`.

The test cases are good examples until I do better documentation!

A very few functions have arguments in a different order to make optional ones easier. This is a bit confusing sometimes, so check the examples or source code.

It would be nice to be API compatible with other projects, especially Luaposix, luasocket, nixio. Unfortunately none of these seem to have test suites.

### Performance

If you want the highest performance, allocate and pass your own buffers, as obviously allocation is expensive. It is now fine to use the string flags for functions, as these are memoized. Check the output of `luajit -jv` to see what is going on and let me know if there are any issues that need fixes for NYI functions. You should be able to get native C like performance.

There is an example epoll script that you can test with Apachebench [in the examples](https://github.com/justincormack/ljsyscall-examples). On my machine apachebench uses more CPU time than the script so the results are a bit low.

### Issues

There will no doubt be bugs and missing features, please report them if you find them. Also API design issues. You can use the [github issue tracker](https://github.com/justincormack/ljsyscall/issues?page=1&state=open)
