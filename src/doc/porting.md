# Porting Snabb Switch

## Background

Snabb Switch is a low-level program. The source code includes device
drivers, assembler code, and optimizations for specific CPU families.

Simplicity, performance, and portability are all important. However,
simplicity and performance have been more *urgent* than portability.
For this reason we have allowed ourselves to focus on:

- Linux/x86-64
- The most popular commodity network adapters
- Optimizations for Intel "Sandy Bridge" and later processors

This allows us to create simple and performant software but it also
means that porting work is necessary to support further platforms.

## How to port Snabb Switch

Suppose you want to run Snabb Switch on a new CPU architecture (i386,
ARM, PPC, ...) or a new operating system (FreeBSD, SmartOS, Windows,
...). How do you do it?

The short answer is that you run the test suite, see what breaks, and
keep fixing things until the functional tests succeed and the
performance tests yield adequate results. Once you are satisfied with
the results you have ported Snabb Switch: congratulations!

You can submit your port in a Pull Request to have it merged
"upstream" onto the master branch. This will be accepted if the
community deems the port to be a net benefit. In that case the
project will also acquire the relevant hardware and provide automatic
test coverage via our [Continuous Integration](http://mr.gy/blog/snabb-ci.html)
system.

If you are actively working on a port that you plan to complete then
you can advertise this fact by adding your development branch to
[branches.md](branches.md). This will help potential contributions to
find your work.

If you are not sure where to start then you are welcome gather
feedback by filing an Issue or a Pull Request with some draft code.
However, don't expect portability code to be merged until it is
complete enough to be useful for end-users and has test coverage. (If
you update the C sources with `#ifdef WIN32` sections then this only
becomes interesting for the master branch once it means that users can
actually run the software on the new platform.)

## Notes on challenges

Here are a few challenges you are likely to encounter when porting
Snabb Switch:

- The `memory` module encodes the physical address of DMA memory into its virtual address using a 64-bit tagging scheme. This would need to be adapted for a 32-bit CPU.
- Device drivers depend on allocating physically contiguous memory in blocks of at least 10KB.
- Virtio-net code assumes a strict (x86-like) memory model that does not reorder stores. If your processor provides a more relaxed memory model then additional hardware memory barrier operations will be needed.
- The shm/counter mechanism assumes that the processor loads and stores 64-bit values atomically. If your processor does not provide atomic 64-bit loads and stores then additional synchronization may be needed.
- Certain optimizations depend on specific instruction set extensions such as AVX2. These optimizations may need to be ported in order to achieve adequate performance. (Particularly: multiple SIMD-optimized IP checksum routines.)
- Certain functions may only be available platform-specific optimized variants. You would either need to live without these routines, or write a generic fallback routine, or write a new optimized variant. (Particularly: AES-GCM encryption with Intel AES-NI instructions.)

Like we said: Snabb Switch is a low-level piece of
software. Portability is important but simplicity and performance are
urgent.

Good luck!

