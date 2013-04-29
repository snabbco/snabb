#include <assert.h>
#include <fcntl.h>
#include <linux/vhost.h>
#include <linux/virtio_ring.h>
#include <stdint.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <unistd.h>

#include "virtio.h"
#include "vhost_client.h"

static int setup_vring(struct vio *vio, int index); // forward declaration

/* Open vhost I/O on given TAP file descriptor and specified memory
   range. The caller is responsible for passing a valid tap file
   descriptor and memory structure but not for initializing the vio
   struct.

   Return 0 on success.

   See this link for a discussion of the Linux/KVM vhost_net feature:
   http://blog.vmsplice.net/2011/09/qemu-internals-vhost-architecture.html */
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

/* Setup vhost memory mapping for sockfd (a tap device or raw socket).
   The memory mapping tells the kernel how to interpret addresses that
   we write in our vring for virtio_net.

   This should be called each time new DMA memory is introduced into
   the process after an initial call to vhost_open().

   Return 0 on success. */
int vhost_set_memory(struct vio *vio, struct vio_memory *memory)
{
  return ioctl(vio->vhostfd, VHOST_SET_MEM_TABLE, memory);
}
