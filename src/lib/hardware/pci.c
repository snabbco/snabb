#include <assert.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

/// ### Access PCI devices using Linux sysfs (`/sys`) filesystem
///
/// sysfs is an interface towards the Linux kernel based on special
/// files that are implemented as callbacks into the kernel. Here are
/// some background links about sysfs:
///
/// - High-level: <http://en.wikipedia.org/wiki/Sysfs>
/// - Low-level:  <https://www.kernel.org/doc/Documentation/filesystems/sysfs.txt>

/// PCI hardware device registers can be memory-mapped via sysfs for
/// "Memory-Mapped I/O" by device drivers. The trick is to `mmap()` a file
/// such as:
///         /sys/bus/pci/devices/0000:00:04.0/resource0
/// and then read and write that memory to access the device.

// Open a PCI resource for memory-mapped I/O.
// Lock the resource for exclusive access.
int open_pci_resource(const char *path)
{
  int fd;
  if ((fd = open(path, O_RDWR | O_SYNC)) == -1) {
    return -1;
  }
  if (flock(fd, LOCK_EX|LOCK_NB) == -1) {
    fprintf(stderr, "failed to lock %s\n", path);
    close(fd);
    return -1;
  }
  return fd;
}

// Return a point to the mapped memory, or NULL on failure.
uint32_t *map_pci_resource(int fd)
{
  void *ptr;
  struct stat st;
  assert( fstat(fd, &st) == 0 );
  ptr = mmap(NULL, st.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (ptr == MAP_FAILED) {
    return NULL;
  } else {
    return (uint32_t *)ptr;
  }
}

void close_pci_resource(int fd, uint32_t *addr)
{
  flock(fd, LOCK_UN);
  if (addr != NULL) {
    struct stat st;
    assert( fstat(fd, &st) == 0 );
    assert( munmap((void *)addr, st.st_size) == 0 );
  }
  close(fd);
}

/// Little convenience function for Lua to open the `config` PCI sysfs
/// file. (XXX Is there an easy way to do this directly in Lua?)
int open_pcie_config(const char *path)
{
  return open(path, O_RDWR);
}
