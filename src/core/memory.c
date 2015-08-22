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
//
// This also means that it's possible to pass pointers to objects
// within this area between different processes.  For this, the
// global variable map_ids must point to a shared object,  If not null,
// it's used to store the mapping IDs of each hugepage, so that
// allocate_on_sigsegv() can map the same pages on demand.


#define _GNU_SOURCE

#include <assert.h>
#include <fcntl.h>
#include <signal.h>
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

#define ARRAY_SIZE(A) (sizeof(A)/sizeof(A[0]))


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
  uint64_t physical_address, virtual_address;
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
  //shmctl(shmid, IPC_RMID, 0);

  // write shm id to a mmap()ed structure.
  if (map_ids) {
    int offst = physical_address >> map_ids->huge_page_bits;
    assert(offst < ARRAY_SIZE(map_ids->ids));
    map_ids->ids[offst] = shmid;
  }

  return realptr;
 fail:
  if (tmpptr  != MAP_FAILED) { shmdt(tmpptr); }
  if (realptr != MAP_FAILED) { shmdt(realptr); }
  if (shmid   != -1)         { shmctl(shmid, IPC_RMID, 0); }
  return NULL;
}

// SIGSEGV handler: attempts map packet memory on demand
void allocate_on_sigsegv(int sig, siginfo_t *si, void *unused)
{
  uint64_t address = (uint64_t)si->si_addr;
  if ((address & 0x500000000000ULL) != 0x500000000000ULL) {
    // This is not DMA memory: die.
    //exit(139);
  } else {
    uint64_t physaddr = address  & ~0x500000000000ULL;
    uint64_t physpage = physaddr & ~(2*1024*1024-1);
    uint64_t virtpage = address  & ~(2*1024*1024-1);

    int offst = physpage >> map_ids->huge_page_bits;
    assert(offst < ARRAY_SIZE(map_ids->ids));
    int id = map_ids->ids[offst];

    shmat(id, (void*)virtpage, 0);
  }
}

void setup_signal()
{
  if (map_ids) {
    struct sigaction sa;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);
    sa.sa_sigaction = allocate_on_sigsegv;
    assert(sigaction(SIGSEGV, &sa, NULL) != -1);
  }
}


void cleanup_hugepage_shms()
{
  if (!map_ids) return;

  int i = 0;
  for (i=0; i < ARRAY_SIZE(map_ids->ids); i++) {
    int shmid = map_ids->ids[i];
    if (shmid != 0) {
      shmctl(shmid, IPC_RMID, 0);
    }
  }
}
