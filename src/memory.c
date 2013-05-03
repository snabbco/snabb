#include <assert.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>

/// ### HugeTLB page allocation

/* Allocate a HugeTLB memory page of 'size' bytes.
   Return NULL if such a page cannot be allocated.*/
void *allocate_huge_page(int size)
{
  void *ptr = mmap(NULL, size, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, 0, 0);
  return ptr != MAP_FAILED ? ptr : NULL;
}

/// ### Stable physical memory access

/* Lock the physical address of all virtual memory in the process.
   This is effective for all current and future memory allocations.
   Returns 0 on success or -1 on error. */
int lock_memory()
{
  return mlockall(MCL_CURRENT | MCL_FUTURE);
}

/* Create a mapping from physical memory to virtual memory.
   Return a pointer to the virtual memory, or NULL on failure. */
void *map_physical_ram(uint64_t start, uint64_t end, bool cacheable)
{
  int fd;
  void *ptr;
  assert( (fd = open("/dev/mem", O_RDWR | (cacheable ? 0 : O_SYNC))) >= 0 );
  ptr = mmap(NULL, end-start, PROT_READ | PROT_WRITE, MAP_SHARED, fd, start);
  close(fd);
  if (ptr == MAP_FAILED) {
    return NULL;
  } else {
    return ptr;
  }
}

static int pagemap_fd;

/* Return the physical page index of the given virtual page index.
   That is: convert from virtual process address space to physical
   memory address. */
uint64_t phys_page(uint64_t virt_page)
{
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

