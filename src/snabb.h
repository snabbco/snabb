/* snabb.h - interface for libsnabb: the C backend of Snabb Switch.
 *
 * Copyright 2012 Snabb GmbH. See the file COPYING for license details. */

/* Return the current wall-clock time in nanoseconds. */
uint64_t get_time_ns();

/* Open a 'snabb_shm' QEMU/KVM shared memory ethernet device.
   This is a shared memory area where ethernet frames can be exchanged
   with the hypervisor. */
struct snabb_shm_dev *open_shm(const char *path);

/* Open a Linux TAP device and return its file descriptor, or -1 on error.

   TAP is a virtual network device where we can exchange ethernet
   frames with the host kernel.

   'name' is the name of the host network interface, e.g. 'tap0', or
   an empty string if a name should be provisioned on demand. */
int open_tap(const char *name);

/* Map PCI device memory into the process via a sysfs PCI resource file.
   Return a point to the mapped memory, or NULL on failure.

   'path' is for example /sys/bus/pci/devices/0000:00:04.0/resource0

   XXX Close file discipline? */
void *map_pci_resource(const char *path);

/* Map physical memory into the process.
   Return a pointer to the mapped memory, or NULL on failure. */
void *map_physical_ram(uint64_t start, uint64_t end, bool cacheable);

