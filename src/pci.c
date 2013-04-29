#include <assert.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <unistd.h>

/* Map PCI device memory into the process via a sysfs PCI resource file.
   Return a point to the mapped memory, or NULL on failure.

   'path' is for example /sys/bus/pci/devices/0000:00:04.0/resource0 */
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

/* Open Linux sysfs PCIe configuration file for read/write. */
int open_pcie_config(const char *path)
{
  return open(path, O_RDWR);
}
