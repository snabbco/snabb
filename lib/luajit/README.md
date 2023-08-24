<p align="center"><img src="doc/raptorjit.png" alt="RaptorJIT"></p>

[![Build Status](https://travis-ci.org/raptorjit/raptorjit.svg?branch=master)](https://travis-ci.org/raptorjit/raptorjit)

**RaptorJIT** is a Lua implementation suitable for high-performance
low-level system programming. If you want to use a simple dynamic
language to write a network stack; a hypervisor; a unikernel; a
database; etc, then you have come to the right place.

RaptorJIT is a fork of [LuaJIT](https://luajit.org/) where we aim to
provide:

- Ubiquitous tracing and profiling to make application
  performance and compiler behaviour transparent to programmers.
- Interactive tools for inspecting and cross-referencing
  trace and profiler data ([Studio](https://github.com/studio/studio/)).
- Collaborative and distributed development based on the Linux kernel
  fork-and-merge model.

The most notable technical changes since forking LuaJIT are:

- Added `auditlog` and `vmprofile` low-overhead ("always on") binary
  tracing and profiler logging features. Removed obsoleted tracing
  based on introspection including `jit.v`, `jit.dump`, and `jit.p`.
- Reduced code maintenance footprint ~50% by removing `#ifdef`
  features that are not required for Linux/x86-64 e.g. Windows
  support, 32-bit heap support, and non-x86 backends. This is a
  necessary short-term expedient to make the code maintainable while
  we bootstrap the project.
- Compiler heuristics tightened to reduce the risk of bytecode
  blacklisting causing catastrophic performance drops.
- Started using `git merge` to accept contributions of both code and
  development history from other forks.

RaptorJIT is used successfully by
the [Snabb](https://github.com/snabbco/snabb) community to develop
high-performance production network equipment. Join us!

### RaptorJIT compilation for users

Build using LuaJIT to bootstrap the VM:

```shell
$ make  # requires LuaJIT (2.0 or 2.1) to run DynASM
```

Build without bootstrapping, when not hacking the VM:

```shell
$ make reusevm  # Reuse reference copy of the generated VM code
$ make          # Does not require LuaJIT now
```

### Inspecting trace and profiler data interactively

To understand how your program executes you first produce diagnostic data (*auditlog* and *vmprofile* files) and then you inspect them interactively with [Studio](https://github.com/studio/studio).

You can produce diagnostic data on the command line:

```shell
$ raptorjit -a audit.log -p default.vmprofile ...
```

Or within your Lua code:

```lua
jit.auditlog("audit.log")
local vmprofile = require("jit.vmprofile")
vmprofile.open("default.vmprofile")
```

Then you can copy the file `audit.log` and `*.vmprofile` into a
directory `/somepath` and inspect that with the Studio script:

```
with import <studio>;
raptorjit.inspect /somepath
```

Studio will then parse, analyze, cross-reference, etc, the diagnostic
data and present an interactive user-interface for browsing how the
program ran.

Here are tutorial videos for Studio:

- [How to load Snabb diagnostic data into Studio](https://www.youtube.com/watch?v=x6e1vFFpq5Q). Covers installing Studio and running a script. (Uses a Snabb-specific mechanism for producing diagnostic data which is implemented in Lua.)
- [Inspecting RaptorJIT IR code with Studio](https://www.youtube.com/watch?v=MQyxXSPXcwg). Covers profiling and inspecting small Lua scripts. Runs Lua code directly from the Studio UI.

### RaptorJIT compilation for VM hackers

RaptorJIT uses [Nix](http://nixos.org/nix/) to provide a reference
build environment. You can use Nix to build/test/benchmark RaptorJIT
with suitable versions of all dependencies provided.

Note: Building with nix will be slow the first time because it
downloads the exact reference versions of the toolchain (gcc, etc)
and all dependencies (glibc, etc). This is all cached for future
builds.

#### Build with nix

Install nix:

```
$ curl https://nixos.org/nix/install | sh
```

Build in batch-mode and run the test suite (option 1a):

```shell
$ nix-build    # produces result/bin/raptorjit
```

Build in batch-mode without the test suite (option 1b):

```shell
$ nix-build -A raptorjit
```

Build interactively (option 2):

```shell
$ nix-shell    # start sub-shell with pristine build environment in $PATH
[nix-shell]$ make -j    # build manually as many times as you like
[nix-shell]$ exit       # quit when done
```

#### Build without nix

```shell
$ make
```

... but make sure you have at least `make`, `gcc`, and `luajit` in your `$PATH`.

### Run the benchmarks

Nix can also run the full benchmark suite and generate visualizations
with R/ggplot2.

The simplest incantation tests one branch:

```shell
$ nix-build testsuite/bench --arg Asrc ./.   # note: ./. means ./
```

You can also test several branches (A-E), give them names, specify
command-line arguments, say how many tests to run, and allow parallel
execution:

```shell
# Run the benchmarks and create result visualizations result/
$ nix-build testsuite/bench                     \
            --arg    Asrc ~/git/raptorjit       \
            --argstr Aname master               \
            --arg    Bsrc ~/git/raptorjit-hack  \
            --argstr Bname hacked               \
            --arg    Csrc ~/git/raptorjit-hack2 \
            --argstr Cname hacked-O1            \
            --argstr Cargs -O1                  \
            --arg    runs 100                   \
            -j 5           # Run up to 5 tests in parallel
```

If you are using a distributed nix environment such
as [Hydra](https://nixos.org/hydra/) then the tests can be
automatically parallelized and distributed across a suitable build
farm.

### Optimization resources

These are the authoritative optimization resources for processors
supported by RaptorJIT. If you are confused by references to CPU
details in discussions then these are the places to look for answers.

- [Computer Architecture: A Quantitative Approach](https://www.amazon.com/Computer-Architecture-Fifth-Quantitative-Approach/dp/012383872X) by Hennessy and Patterson.
- [Intel Architectures Optimization Reference Manual](http://www.intel.com/content/www/us/en/architecture-and-technology/64-ia-32-architectures-optimization-manual.html).
- Agner Fog's [software optimization resources](http://www.agner.org/optimize/):
    - [Instruction latency and throughput tables](http://www.agner.org/optimize/instruction_tables.pdf).
    - [Microarchitecture of Intel, AMD, and VIA CPUs](http://www.agner.org/optimize/microarchitecture.pdf).
    - [Optimizing subroutines in assembly language for x86](http://www.agner.org/optimize/optimizing_assembly.pdf).

The [AnandTech review of the Haswell microarchitecture](http://www.anandtech.com/show/6355/intels-haswell-architecture) is also excellent lighter reading.

### Quotes

Here are some borrowed words to put this branch into context:

> I'm outta here in a couple of days. Good luck. You'll need it.
> _[Mike Pall](http://www.freelists.org/post/luajit/Turning-Lua-into-C-was-alleviate-the-load-of-the-GC)_

> Optimal code is not optimal to maintain. _[Vyacheslav Egorov](https://www.youtube.com/watch?v=EaLboOUG9VQ)_

> If a programmer is indispensable, get rid of him as quickly as possible. _[Gerald M. Weinberg](https://www.amazon.com/Psychology-Computer-Programming-Silver-Anniversary/dp/0932633420)_

> If a system is to serve the creative spirit, it
> must be entirely comprehensible to a single individual. _[Dan
> Ingalls](https://www.cs.virginia.edu/~evans/cs655/readings/smalltalk.html)_

> The competent programmer is fully aware of the strictly limited size of his own skull; therefore he approaches the programming task in full humility, and among other things he avoids clever tricks like the plague. _[E.W. Dijkstra](https://www.cs.utexas.edu/~EWD/transcriptions/EWD03xx/EWD340.html)_

> There are two ways of constructing a software design: One way is to make it so simple that there are obviously no deficiencies, and the other way is to make it so complicated that there are no obvious deficiencies. The first method is far more difficult. _[C.A.R. Hoare](http://zoo.cs.yale.edu/classes/cs422/2014/bib/hoare81emperor.pdf)_

> Everyone knows that debugging is twice as hard as writing a program in the first place. So if you're as clever as you can be when you write it, how will you ever debug it? _[Brian Kernighan](http://www2.ing.unipi.it/~a009435/issw/extra/kp_elems_of_pgmng_sty.pdf)_

