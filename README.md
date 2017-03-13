# RaptorJIT

[![Build Status](https://travis-ci.org/raptorjit/raptorjit.svg?branch=master)](https://travis-ci.org/raptorjit/raptorjit)

RaptorJIT is an experimental fork of LuaJIT. Premise: What would I do
if I were only trying to please myself and nobody else?

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

Goal is to strip the code down to the minimum that is needed for
writing high-performance soft-realtime server applications for
Linux/x86-64. PRs with radical code reductions welcome! :-)

### Quotes

Here are some borrowed words to put this branch into context:

> Personal Mastery: If a system is to serve the creative spirit, it
> must be entirely comprehensible to a single individual. _Dan
> Ingalls_

> The competent programmer is fully aware of the strictly limited size
> of his own skull. _E.W. Dijkstra_

> Debugging is twice as hard as writing the code in the first place.
> Therefore, if you write the code as cleverly as possible, you are,
> by definition, not smart enough to debug it. _Brian Kernighan_

> Optimal code is not optimal to maintain. _Vyacheslav Egorov_

> I'm outta here in a couple of days. Good luck. You'll need it.
> _[Mike Pall](http://www.freelists.org/post/luajit/Turning-Lua-into-C-was-alleviate-the-load-of-the-GC)_

