/* virtio.h - Virtual I/O device support in Linux/KVM style
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 * Copyright 2013 Luke Gorrie.
 */

enum { SNABB_VIRTIO_RING_SIZE = 256; }

// Based on the specification:
//   virtio: Towards a De-Facto Standard For Virtual I/O Devices (Rusty Russell)
//   http://ozlabs.org/~rusty/virtio-spec/virtio-paper.pdf

struct vring_desc {
  uint64_t addr;
  uint32_t len;
  uint16_t flags;
  uint16_t next;
};

struct vring_avail {
  uint16_t flags;
  uint16_t idx;
  uint16_t ring[SNABB_VIRTIO_RING_SIZE];
};

struct vring_used_elem {
  uint32_t id;
  uint32_t len;
};

struct vring_used {
  uint16_t flags;
  uint16_t len;
  struct vring_used_elem ring[SNABB_VIRTIO_RING_SIZE];
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
  VIRTIO_NET_HDR_F_NEEDS_CSUM = 1 // use csum_start, csum_offset
};

enum { // virtio_net_hdr.gso_type
  VIRTIO_NET_HDR_GSO_NONE  = 0,
  VIRTIO_NET_HDR_GSO_TCPV4 = 1,
  VIRTIO_NET_HDR_GSO_UDP   = 3,
  VIRTIO_NET_HDR_GSO_TCPV6 = 4,
  VIRTIO_NET_HDR_GSO_ECN   = 0x80
};

enum {
  // Maximum elements in vhost_memory.regions
  VHOST_MEMORY_MAX_NREGIONS = 64,
  // Region addresses and sizes must be 4K aligned
  VHOST_PAGE_SIZE = 0x1000
}

struct vhost_memory_region {
  uint64_t guest_phys_addr;
  uint64_t memory_size;
  uint64_t userspace_addr;
  uint64_t flags_padding; // no flags currently specified
};

struct vhost_memory {
  uint32_t nregions;
  uint32_t padding;
  struct vhost_memory_region regions[VHOST_MEMORY_MAX_NREGIONS];
};

// Snabb Switch data structures

struct snabb_vhost {
  // tap device / raw socket file descriptor
  int tapfd;
  // eventfd(2) for kernel to tell us when traffic is ready
  int eventfd;
};

