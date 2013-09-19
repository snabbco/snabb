#include <assert.h>
#include <fcntl.h>
//#include <linux/vhost.h>
//#include <linux/virtio_ring.h>
#include <stdint.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <unistd.h>

#include "lib/virtio/virtio_vring.h"
#include "vhost.h"
#include "vhost_client.h"

static int setup_vring(struct vhost *vhost, int index); // forward declaration

/* Open vhost I/O on given TAP file descriptor and specified memory
   range. The caller is responsible for passing a valid tap file
   descriptor and memory structure but not for initializing the vhost
   struct.

   Return 0 on success.

   See this link for a discussion of the Linux/KVM vhost_net feature:
   http://blog.vmsplice.net/2011/09/qemu-internals-vhost-architecture.html */
int vhost_open(struct vhost *vhost, int tapfd, struct vhost_memory *memory)
{
  vhost->tapfd = tapfd;
  if ((vhost->vhostfd = open("/dev/vhost-net", O_RDWR)) < 0 ||
      (ioctl(vhost->vhostfd, VHOST_SET_OWNER, NULL)) < 0 ||
      (ioctl(vhost->vhostfd, VHOST_GET_FEATURES, &vhost->features)) < 0 ||
      vhost_set_memory(vhost, memory) ||
      setup_vring(vhost, 0) < 0 ||
      setup_vring(vhost, 1) < 0) {
    /* Error */
    if (vhost->vhostfd >= 0) { close(vhost->vhostfd); vhost->vhostfd = -1; }
    return -1;
  }
  return 0;
}

static int setup_vring(struct vhost *vhost, int index)
{
  struct vhost_vring *vring = &vhost->vring[index];
  vring->kickfd = eventfd(0, EFD_NONBLOCK);
  vring->callfd = eventfd(0, EFD_NONBLOCK);
  assert(vring->kickfd >= 0);
  assert(vring->callfd >= 0);
  struct vhost_vring_file  backend = { .index = index, .fd = vhost->tapfd };
  struct vhost_vring_state num  = { .index = index, .num = VHOST_VRING_SIZE };
  struct vhost_vring_state base = { .index = index, .num = 0 };
  struct vhost_vring_file  kick = { .index = index, .fd = vring->kickfd };
  struct vhost_vring_file  call = { .index = index, .fd = vring->callfd };
  struct vhost_vring_addr  addr = { .index = index,
                                    .desc_user_addr  = (uint64_t)&vring->desc,
                                    .avail_user_addr = (uint64_t)&vring->avail,
                                    .used_user_addr  = (uint64_t)&vring->used,
                                    .log_guest_addr  = (uint64_t)NULL,
                                    .flags = 0 };
  return (ioctl(vhost->vhostfd, VHOST_SET_VRING_NUM,  &num)  ||
          ioctl(vhost->vhostfd, VHOST_SET_VRING_BASE, &base) ||
          ioctl(vhost->vhostfd, VHOST_SET_VRING_KICK, &kick) ||
          ioctl(vhost->vhostfd, VHOST_SET_VRING_CALL, &call) ||
          ioctl(vhost->vhostfd, VHOST_SET_VRING_ADDR, &addr) ||
          ioctl(vhost->vhostfd, VHOST_NET_SET_BACKEND, &backend));
}

/* Setup vhost memory mapping for sockfd (a tap device or raw socket).
   The memory mapping tells the kernel how to interpret addresses that
   we write in our vring for virtio_net.

   This should be called each time new DMA memory is introduced into
   the process after an initial call to vhost_open().

   Return 0 on success. */
int vhost_set_memory(struct vhost *vhost, struct vhost_memory *memory)
{
  return ioctl(vhost->vhostfd, VHOST_SET_MEM_TABLE, memory);
}
