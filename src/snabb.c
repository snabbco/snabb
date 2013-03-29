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
#include <sys/eventfd.h>
#include <time.h>
#include <unistd.h>
#include <linux/vhost.h>
#include <linux/virtio_ring.h>

#include "virtio.h"
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

void *allocate_huge_page(int size)
{
  void *ptr = mmap(NULL, size, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, 0, 0);
  return ptr != MAP_FAILED ? ptr : NULL;
}

/* forward declaration */
static int setup_vring(struct vio *vio, int index);

int vhost_open(struct vio *vio, int tapfd, struct vio_memory *memory)
{
  vio->tapfd = tapfd;
  if ((vio->vhostfd = open("/dev/vhost-net", O_RDWR)) < 0 ||
      (ioctl(vio->vhostfd, VHOST_SET_OWNER, NULL)) < 0 ||
      (ioctl(vio->vhostfd, VHOST_GET_FEATURES, &vio->features)) < 0 ||
      vhost_set_memory(vio, memory) ||
      setup_vring(vio, 0) < 0 ||
      setup_vring(vio, 1) < 0) {
    /* Error */
    if (vio->vhostfd >= 0) { close(vio->vhostfd); vio->vhostfd = -1; }
    return -1;
  }
  return 0;
}

static int setup_vring(struct vio *vio, int index)
{
  struct vio_vring *vring = &vio->vring[index];
  vring->kickfd = eventfd(0, EFD_NONBLOCK);
  vring->callfd = eventfd(0, EFD_NONBLOCK);
  assert(vring->kickfd >= 0);
  assert(vring->callfd >= 0);
  struct vhost_vring_file  backend = { .index = index, .fd = vio->tapfd };
  struct vhost_vring_state num  = { .index = index, .num = VIO_VRING_SIZE };
  struct vhost_vring_state base = { .index = index, .num = 0 };
  struct vhost_vring_file  kick = { .index = index, .fd = vring->kickfd };
  struct vhost_vring_file  call = { .index = index, .fd = vring->callfd };
  struct vhost_vring_addr  addr = { .index = index,
                                    .desc_user_addr  = (uint64_t)&vring->desc,
                                    .avail_user_addr = (uint64_t)&vring->avail,
                                    .used_user_addr  = (uint64_t)&vring->used,
                                    .log_guest_addr  = (uint64_t)NULL,
                                    .flags = 0 };
  return (ioctl(vio->vhostfd, VHOST_SET_VRING_NUM,  &num)  ||
          ioctl(vio->vhostfd, VHOST_SET_VRING_BASE, &base) ||
          ioctl(vio->vhostfd, VHOST_SET_VRING_KICK, &kick) ||
          ioctl(vio->vhostfd, VHOST_SET_VRING_CALL, &call) ||
          ioctl(vio->vhostfd, VHOST_SET_VRING_ADDR, &addr) ||
          ioctl(vio->vhostfd, VHOST_NET_SET_BACKEND, &backend));
}

int vhost_set_memory(struct vio *vio, struct vio_memory *memory)
{
  return ioctl(vio->vhostfd, VHOST_SET_MEM_TABLE, memory);
}

void full_memory_barrier()
{
  // See http://gcc.gnu.org/onlinedocs/gcc-4.1.1/gcc/Atomic-Builtins.html
  __sync_synchronize();
}

void sleep_ns(int nanoseconds)
{
  static struct timespec time;
  struct timespec rem;
  time.tv_nsec = nanoseconds;
  nanosleep(&time, &rem);
}

