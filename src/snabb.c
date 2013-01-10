/* Copyright 2012 Snabb GmbH. See the file COPYING for license details. */

#include <assert.h>
#include <fcntl.h>
#include <linux/if_tun.h>
#include <net/if.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include "snabb.h"
#include "snabb-shm-dev.h"

int lock_memory()
{
  return mlockall(MCL_CURRENT | MCL_FUTURE);
}

struct snabb_shm_dev *open_shm(const char *path)
{
    int fd;
    struct snabb_shm_dev *dev;
    assert( (fd = open(path, O_RDWR)) >= 0 );
    dev = (struct snabb_shm_dev *)
        mmap(NULL, sizeof(struct snabb_shm_dev),
             PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
    assert( dev != MAP_FAILED );
    assert( dev->magic == 0x57ABB000 );
    return dev;
}

int open_tap(const char *name)
{
    struct ifreq ifr;
    int fd;
    if ((fd = open("/dev/net/tun", O_RDWR | O_NONBLOCK)) < 0) {
        perror("open /dev/net/tun");
        return -1;
    }
    memset(&ifr, 0, sizeof(ifr));
    ifr.ifr_flags = IFF_TAP | IFF_NO_PI;
    strncpy(ifr.ifr_name, name, sizeof(ifr.ifr_name)-1);
    if (ioctl(fd, TUNSETIFF, (void*)&ifr) < 0) {
        perror("TUNSETIFF");
        return -1;
    }
    return fd;
}

uint64_t get_time_ns()
{
    /* XXX Consider using RDTSC. */
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

void *map_pci_resource(const char *path)
{
  int fd;
  void *ptr;
  struct stat st;
  assert( (fd = open(path, O_RDWR | O_SYNC)) >= 0 );
  assert( fstat(fd, &st) == 0 );
  ptr = mmap(NULL, st.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (ptr == MAP_FAILED) {
    return NULL;
  } else {
    return ptr;
  }
}

void *map_physical_ram(uint64_t start, uint64_t end, bool cacheable)
{
  int fd;
  void *ptr;
  assert( (fd = open("/dev/mem", O_RDWR | (cacheable ? 0 : O_SYNC))) >= 0 );
  ptr = mmap(NULL, end-start, PROT_READ | PROT_WRITE, MAP_SHARED, fd, start);
  if (ptr == MAP_FAILED) {
    return NULL;
  } else {
    return ptr;
  }
}

int open_pcie_config(const char *path)
{
  return open(path, O_RDWR);
}

static int pagemap_fd;

uint64_t pagemap_info(uint64_t virt_page)
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
  return data;
}

void *allocate_huge_page(int size)
{
  void *ptr = mmap(NULL, size, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, 0, 0);
  return ptr != MAP_FAILED ? ptr : NULL;
}

