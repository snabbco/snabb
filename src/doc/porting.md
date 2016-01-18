# Porting Snabb Switch

Snabb Switch targets Linux/x86-64 on the master branch. The source
code includes device drivers, assembler code, and optimization for
specific CPU families.

You are welcome to port Snabb Switch to a new platform. To do this you
can create a branch for your port and advertise this in
[branches.md](branches.md). See below for some technical tips.

Currently there is no roadmap for supporting more platforms on the
master branch. The first step in this direction would be to have a
well-maintained port that is important for users.

The master branch accepts code that is specific to Linux/x86-64. It
does not accept code intended for other platforms.

## Technical tips

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

