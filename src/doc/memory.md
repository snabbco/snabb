Snabb Switch does two things specially when it comes to memory: it
runs with a fixed physical memory map and it allocates "huge pages"
from the operating system.

Running with a fixed memory map means that every virtual address in
the Snabb Switch process has a fixed "physical address" in the RAM
chips. This means that we are always able to convert from a virtual
address in our process to a physical address that other hardware (for
example, a network card) can use for DMA.

Huge pages (aka HugeTLB pages) are how we allocate large amounts of
contiguous memory, typically 2MB at a time. Hardware devices sometimes
require this, for example a network card's "descriptor ring" may
require a 1MB list of pointers to available buffers.

For more information about huge pages checkout [HugeTLB - Large Page Support in the Linux kernel](http://linuxgazette.net/155/krishnakumar.html) in Linux Gazette and [linux/Documentation/vm/hugetlbpage.txt](https://www.kernel.org/doc/Documentation/vm/hugetlbpage.txt) in the Linux kernel sources.

    FIXME: Without this code line, the memory.c source gets formatted as prose.
