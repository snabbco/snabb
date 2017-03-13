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
  with [automatic performance regression tests](https://github.com/lukego/LuaJIT-branch-tests).

Goal is to strip the code down to the minimum that is needed for
writing high-performance soft-realtime server applications for
Linux/x86-64. PRs with radical code reductions welcome! :-)

-- Luke Gorrie @lukego

