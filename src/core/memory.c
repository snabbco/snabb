#define _GNU_SOURCE

#include <stdlib.h>
#include <assert.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>
#include <string.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include "memory.h"
#define MEMORY_HUGETLB_TAG       0x500000000000ULL
#define MEMORY_HUGETLB_TAG_MASK  0xFF0000000000ULL
#define MEMORY_HUGETLB_ADDR_MASK 0x00FFFFFFFFFFULL

/// ### HugeTLB page allocation

// Convert from virtual addresses in our own process address space to
// physical addresses in the RAM chips.
uint64_t virtual_to_physical(void *ptr)
{
  uint64_t virt_page;
  static int pagemap_fd;
  virt_page = ((uint64_t)ptr) / 4096;
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
  return (data & ((1ULL << 55) - 1)) * 4096;
}

// Allocate a HugeTLB memory page of 'size' bytes.
// Optionally make the page persistent in /hugetlbfs/snabb/
//
// Return a pointer to the start of the page, or NULL on failure.
void *allocate_huge_page(int size, bool persistent)
{
  int fd = -1;
  char tmpfilename[256], realfilename[256];
  uint64_t physical_address, virtual_address;
  void *tmpptr, *realptr;
  strncpy(tmpfilename, "/hugetlbfs/snabb/new.XXXXXX", sizeof(tmpfilename));
  mkdir("/hugetlbfs/snabb", 0700);
  if ((fd = mkostemp(tmpfilename, O_RDWR|O_CREAT)) == -1) {
    perror("create new hugetlb file");
    goto fail;
  }
  if (ftruncate(fd, size) == -1) {
    perror("ftruncate");
    goto fail;
  }
  tmpptr = mmap(NULL, size, PROT_READ | PROT_WRITE,
		MAP_SHARED | MAP_HUGETLB, fd, 0);
  if (tmpptr == MAP_FAILED) {
    perror("tmp mmap");
    goto fail;
  }
  if ((physical_address = virtual_to_physical(tmpptr)) == 0) {
    goto fail;
  }
  virtual_address = physical_address | MEMORY_HUGETLB_TAG;
  realptr = mmap((void*)virtual_address, size, PROT_READ | PROT_WRITE,
		 MAP_SHARED | MAP_HUGETLB | MAP_FIXED, fd, 0);
  if (realptr == MAP_FAILED) {
    perror("real mmap");
    return NULL;
  }
  munmap(tmpptr, size);
  if (persistent) {
    snprintf(realfilename, sizeof(realfilename),
	     "/hugetlbfs/snabb/page.%012lx", physical_address);
    if (rename(tmpfilename, realfilename) == -1) {
      perror("rename");
      goto fail;
    }
  } else {
    if (unlink(tmpfilename) == -1) {
      perror("unlink");
      goto fail;
    }
  }
  return realptr;
 fail:
  if (fd != -1) { close(fd); }
  return NULL;
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

