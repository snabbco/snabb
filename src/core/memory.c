#include <assert.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>
#include <numaif.h>

/// ### HugeTLB page allocation

// Allocate a HugeTLB memory page of 'size' bytes.
// Return a pointer to the start of the page, or NULL on failure.
void *allocate_huge_page(int size)
{
  void *ptr = mmap(NULL, size, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, 0, 0);
  if (ptr == MAP_FAILED) {
      return NULL;
  } else {
      return ptr;
  }
}

void *allocate_huge_page_numa(int size, int numa_node)
{
  void *addr;
  unsigned long nodemask = 1 << numa_node;
  // don't mind if this fails: it's only a hint.
  assert(set_mempolicy(MPOL_PREFERRED, &nodemask, sizeof(long)) == 0);
  addr = allocate_huge_page(size);
  assert(set_mempolicy(MPOL_DEFAULT, NULL, sizeof(long)) == 0);
  return addr;
}

/// ### Stable physical memory access

/// Physical addresses are resolved using the Linux
/// [pagemap](https://www.kernel.org/doc/Documentation/vm/pagemap.txt)
/// `procfs` file.

// Lock all current and future virtual memory in a stable physical location.
int lock_memory()
{
  return mlockall(MCL_CURRENT | MCL_FUTURE);
}

// Convert from virtual addresses in our own process address space to
// physical addresses in the RAM chips.
//
// Note: Using page numbers, which are simply addresses divided by 4096.
uint64_t phys_page(uint64_t virt_page)
{
  static int pagemap_fd;
  if (pagemap_fd == 0) {
    if ((pagemap_fd = open("/proc/self/pagemap", O_RDONLY)) <= 0) {
      perror("open pagemap");
      return 0;
    }
  }
  uint64_t data;
  int len;
  len = pread(pagemap_fd, &data, sizeof(data), virt_page * sizeof(uint64_t));
  if (len != sizeof(data)) {
    perror("pread");
    return 0;
  }
  if ((data & (1ULL<<63)) == 0) {
    fprintf(stderr, "page %lx not present: %lx", virt_page, data);
    return 0;
  }
  return data & ((1ULL << 55) - 1);
}

