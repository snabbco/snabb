<p align="center"><img src="doc/raptorjit.png" alt="RaptorJIT"></p>

[![Build Status](https://travis-ci.org/raptorjit/raptorjit.svg?branch=master)](https://travis-ci.org/raptorjit/raptorjit)

**RaptorJIT** is a fork of LuaJIT targeting Linux/x86-64 server applications.

Initial changes (ongoing work):

- Support only Linux/x86-64 with `+JIT +FFI +GC64 +NO_UNWIND` and `-GDBJIT
  -PERFTOOLS -VMEVENT -PROFILE` and otherwise canonical settings.
  Remove the ~50,000 lines of code for other architectures, operating
  systems, and features.
- Remove features that are not the right thing for my use cases:
  built-in disassemblers, `jit.v`, `jit.p`, `jit.dump`, and the VM
  features required to support them. These need to be replaced with
  simple and low-overhead mechanisms that provide data to be analyzed
  be external tools. (Tools will be developed in
  the [Studio](https://github.com/studio) project.)
- Continuous Integration testing
  with [Travis-CI](https://travis-ci.org/raptorjit/raptorjit) and
  with [automatic performance regression tests](https://hydra.snabb.co/job/luajit/branchmarks/benchmarkResults/latest/download/2).

PRs welcome! Shock me with your radical ideas! :-)

### CPU support

RaptorJIT is narrowly focused:

- [Intel Core](https://en.wikipedia.org/wiki/Intel_Core) (i3/i5/i7/Xeon-E) is the only supported CPU family.
- The latest microarchitecture (currently Skylake) is targetted for all new optimizations.
- The previous microarchitecture (currently Haswell) is supported without regressions.
- Older microarchitectures (currently Sandy Bridge and Nehalem) are not supported at all.

We are flexible during the transitions between processor generations
e.g. when the latest microarchitecture is not readily available in all
product families.

Forks focused on other CPU families (Atom, Xeon Phi, AMD, VIA, etc)
are encouraged and may be merged in the future.

### Performance

RaptorJIT takes a quantitive approach to performance. The value of an
optimization must be demonstrated by a reproducible benchmark.
Optimizations that are not demonstrably beneficial for the currently
supported CPUs are removed.

This makes the following classes of pull requests very welcome:

- Adding optimizations that improve a CI benchmark.
- Adding CI benchmarks that demonstrate the value of optimizations.
- Removing optimizations without degrading CI benchmark performance.

The CI benchmark suite will evolve over time starting from the [standard LuaJIT benchmarks](https://hydra.snabb.co/job/luajit/branchmarks/benchmarkResults/latest/download/2) (already covers RaptorJIT) and the [Snabb end-to-end benchmark suite](https://hydra.snabb.co/job/snabb-new-tests/benchmarks-murren-large/benchmark-reports.report-full-matrix/latest/download/2) (must be updated to cover RaptorJIT.)

### Optimization resources

These are the authoritative optimization resources for processors
supported by RaptorJIT. If you are confused by references to CPU
details in discussions then these are the places to look for answers.

- [Computer Architecture: A Quantitiave Approach](https://www.amazon.com/Computer-Architecture-Fifth-Quantitative-Approach/dp/012383872X) by Hennessy and Patterson.
- [Intel Architectures Optimization Reference Manual](http://www.intel.com/content/www/us/en/architecture-and-technology/64-ia-32-architectures-optimization-manual.html).
- Agner Fog's [software optimization resources](http://www.agner.org/optimize/):
    - [Instruction latency and throughput tables](http://www.agner.org/optimize/instruction_tables.pdf).
    - [Microarchitecture of Intel, AMD, and VIA CPUs](http://www.agner.org/optimize/microarchitecture.pdf).
    - [Optimizing subroutines in assembly language for x86](http://www.agner.org/optimize/optimizing_assembly.pdf).

The [AnandTech review of the Haswell microarchitecture](http://www.anandtech.com/show/6355/intels-haswell-architecture) is also excellent lighter reading.

### Compilation

RaptorJIT uses [nix](http://nixos.org/nix/) to define a reproducible
build environment that includes Clang for C and LuaJIT 2.0 for
bootstrapping (see [default.nix](default.nix)). The recommended way to
build RaptorJIT is with nix, which provides the dependencies
automatically, but you can build manually if you prefer.

Building with nix will be slow the first time due to downloading
toolchains and related dependencies. This is all cached for future
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

... but make sure you have at least `make`, `clang`, and `luajit` in your `$PATH`.

### Quotes

Here are some borrowed words to put this branch into context:

> I'm outta here in a couple of days. Good luck. You'll need it.
> _[Mike Pall](http://www.freelists.org/post/luajit/Turning-Lua-into-C-was-alleviate-the-load-of-the-GC)_

> Optimal code is not optimal to maintain. _[Vyacheslav Egorov](https://www.youtube.com/watch?v=EaLboOUG9VQ)_

> If a programmer is indispensible, get rid of him as quickly as possible. _[Gerald M. Weinberg](https://www.amazon.com/Psychology-Computer-Programming-Silver-Anniversary/dp/0932633420)_

> If a system is to serve the creative spirit, it
> must be entirely comprehensible to a single individual. _[Dan
> Ingalls](https://www.cs.virginia.edu/~evans/cs655/readings/smalltalk.html)_

> The competent programmer is fully aware of the strictly limited size of his own skull; therefore he approaches the programming task in full humility, and among other things he avoids clever tricks like the plague. _[E.W. Dijkstra](https://www.cs.utexas.edu/~EWD/transcriptions/EWD03xx/EWD340.html)_

> There are two ways of constructing a software design: One way is to make it so simple that there are obviously no deficiencies, and the other way is to make it so complicated that there are no obvious deficiencies. The first method is far more difficult. _[C.A.R. Hoare](http://zoo.cs.yale.edu/classes/cs422/2014/bib/hoare81emperor.pdf)_

> Everyone knows that debugging is twice as hard as writing a program in the first place. So if you're as clever as you can be when you write it, how will you ever debug it? _[Brian Kernighan](http://www2.ing.unipi.it/~a009435/issw/extra/kp_elems_of_pgmng_sty.pdf)_

