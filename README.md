# RaptorJIT

[![Build Status](https://travis-ci.org/raptorjit/raptorjit.svg?branch=master)](https://travis-ci.org/raptorjit/raptorjit)

RaptorJIT is a fork of LuaJIT targeting Linux/x86-64 server applications.

Initial changes (ongoing work):

- Support only Linux/x86-64 with `+JIT +FFI +GC64` and `-GDBJIT
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

### Compilation

RaptorJIT uses [nix](http://nixos.org/nix/) to define a reproducible
build environment that includes Clang for C and LuaJIT 2.0 for
bootstrapping. The recommended way to build RaptorJIT is with nix,
which provides the dependencies automatically, but you can build
manually if you prefer.

#### Build with nix

Install nix:

```
$ curl https://nixos.org/nix/install | sh
```

Build in batch-mode (option 1):

```shell
$ nix-build    # produces result/bin/raptorjit
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

