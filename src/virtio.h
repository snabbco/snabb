/* virtio.h - Virtual I/O device support in Linux/KVM style
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 */

enum { VIO_VRING_SIZE = 512 };

// Based on the specification:
//   virtio: Towards a De-Facto Standard For Virtual I/O Devices (Rusty Russell)
//   http://ozlabs.org/~rusty/virtio-spec/virtio-paper.pdf

struct vio_desc {
  uint64_t addr;
  uint32_t len;
  uint16_t flags;
  uint16_t next;
};

struct vio_avail {
  uint16_t flags;
  uint16_t idx;
  uint16_t ring[VIO_VRING_SIZE];
};

struct vio_used_elem {
  uint32_t id;
  uint32_t len;
};

struct vio_used {
  uint16_t flags;
  uint16_t idx;
  struct vio_used_elem ring[VIO_VRING_SIZE];
};

// virtio_net networking

struct virtio_net_hdr {
  uint8_t flags;		// See flags enum above
  uint8_t gso_type;		// See GSO type above
  uint16_t hdr_len;
  uint16_t gso_size;
  uint16_t csum_start;
  uint16_t csum_offset;
};

enum { // virtio_net_hdr.flags
  VIO_NET_HDR_F_NEEDS_CSUM = 1 // use csum_start, csum_offset
};

enum { // virtio_net_hdr.gso_type
  VIO_NET_HDR_GSO_NONE  = 0,
  VIO_NET_HDR_GSO_TCPV4 = 1,
  VIO_NET_HDR_GSO_UDP   = 3,
  VIO_NET_HDR_GSO_TCPV6 = 4,
  VIO_NET_HDR_GSO_ECN   = 0x80
};

enum { // vring flags
  VIO_DESC_F_NEXT = 1,	  // Descriptor continues via 'next' field
  VIO_DESC_F_WRITE = 2,   // Write-only descriptor (otherwise read-only)
  VIO_DESC_F_INDIRECT = 4 // 
};

enum {
  // Maximum elements in vhost_memory.regions
  VIO_MEMORY_MAX_NREGIONS = 64,
  // Region addresses and sizes must be 4K aligned
  VIO_PAGE_SIZE = 0x1000
};

struct vio_memory_region {
  uint64_t guest_phys_addr;
  uint64_t memory_size;
  uint64_t userspace_addr;
  uint64_t flags_padding; // no flags currently specified
};

struct vio_memory {
  uint32_t nregions;
  uint32_t padding;
  struct vio_memory_region regions[VIO_MEMORY_MAX_NREGIONS];
};

// Snabb Switch data structures

struct vio_vring {
  // eventfd(2) for notifying the kernel (kick) and being notified (call)
  int kickfd, callfd;
  struct vio_desc desc[VIO_VRING_SIZE] __attribute__((aligned(8)));
  struct vio_avail avail               __attribute__((aligned(8)));
  struct vio_used used                 __attribute__((aligned(4096)));
};

struct vio {
  // features negotiated with the kernel
  uint64_t features;
  // tap device / raw socket file descriptor
  int tapfd;
  // fd opened from /dev/vhost-net
  int vhostfd;
  struct vio_vring vring[2];
};

