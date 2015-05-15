// memory.c -- allocate dma-friendly memory
//
// Allocate HugeTLB memory pages for DMA. HugeTLB memory is always
// mapped to a virtual address with a specific scheme:
//
//   virtual_address = physical_address | 0x500000000000ULL
//
// This makes it possible to resolve physical addresses directly from
// virtual addresses (remove the tag bits) and to test addresses for
// validity (check the tag bits).

#define _GNU_SOURCE

#include <assert.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ipc.h>
#include <sys/mman.h>
#include <sys/shm.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "memory.h"

// Convert from virtual addresses in our own process address space to
// physical addresses in the RAM chips.
intptr_t virtual_to_physical(intptr_t *ptr)
{
  intptr_t virt_page;
  static int pagemap_fd;
  virt_page = ((intptr_t)ptr) / 4096;
  if (pagemap_fd == 0) {
    if ((pagemap_fd = open("/proc/self/pagemap", O_RDONLY)) <= 0) {
      perror("open pagemap");
      return 0;
    }
  }
  intptr_t data;
  int len;
  len = pread(pagemap_fd, &data, sizeof(data), virt_page * sizeof(uint64_t));
  if (len != sizeof(data)) {
    perror("pread");
    return 0;
  }
  if ((data & (1ULL<<63)) == 0) {
    fprintf(stderr, "page %p not present: %p", (void*) virt_page,(void*) data);
    return 0;
  }
  return (data & ((1ULL << 55) - 1)) * 4096;
}

// Map a new HugeTLB page to an appropriate virtual address.
//
// The HugeTLB page is allocated and mapped using the shm (shared
// memory) API. This API makes it easy to remap the page to a new
// virtual address after we resolve the physical address.
//
// There are two other APIs for allocating HugeTLB pages but they do
// not work as well:
//
//   mmap() anonymous page with MAP_HUGETLB: cannot remap the address
//   after allocation because Linux mremap() does not seem to work on
//   HugeTLB pages.
//
//   mmap() with file-backed MAP_HUGETLB: the file has to be on a
//   hugetlbfs mounted filesystem and that is not necessarily
//   available.
//
// Happily the shm API is happy to remap a HugeTLB page with an
// additional call to shmat() and does not depend on hugetlbfs.
//
// Further reading:
//   https://www.kernel.org/doc/Documentation/vm/hugetlbpage.txt
//   http://stackoverflow.com/questions/27997934/mremap2-with-hugetlb-to-change-virtual-address
void *allocate_huge_page(int size)
{
  int shmid = -1;
  intptr_t physical_address, virtual_address;
  void *tmpptr = MAP_FAILED;  // initial kernel assigned virtual address
  void *realptr = MAP_FAILED; // remapped virtual address
  shmid = shmget(IPC_PRIVATE, size, SHM_HUGETLB | IPC_CREAT | SHM_R | SHM_W);
  tmpptr = shmat(shmid, NULL, 0);
  if (tmpptr == MAP_FAILED) { goto fail; }
  if (mlock(tmpptr, size) != 0) { goto fail; }
  physical_address = virtual_to_physical(tmpptr);
  if (physical_address == 0) { goto fail; }
  virtual_address = physical_address | 0x500000000000ULL;
  realptr = shmat(shmid, (void*)virtual_address, 0);
  if (realptr == MAP_FAILED) { goto fail; }
  if (mlock(realptr, size) != 0) { goto fail; }
  memset(realptr, 0, size); // zero memory to avoid potential surprises
  shmdt(tmpptr);
  shmctl(shmid, IPC_RMID, 0);
  return realptr;
 fail:
  if (tmpptr  != MAP_FAILED) { shmdt(tmpptr); }
  if (realptr != MAP_FAILED) { shmdt(realptr); }
  if (shmid   != -1)         { shmctl(shmid, IPC_RMID, 0); }
  return NULL;
}

