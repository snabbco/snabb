/* snabb.h - interface for libsnabb: the C backend of Snabb Switch.
 *
 * Copyright 2012 Snabb GmbH. See the file COPYING for license details. */

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

