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
} __attribute__((packed));

struct vio_avail {
  uint16_t flags;
  uint16_t idx;
  uint16_t ring[VIO_VRING_SIZE];
} __attribute__((packed));

struct vio_used_elem {
  uint32_t id;
  uint32_t len;
} __attribute__((packed));

struct vio_used {
  uint16_t flags;
  uint16_t idx;
  struct vio_used_elem ring[VIO_VRING_SIZE];
} __attribute__((packed));

// Feature bits definition.

enum {
  VIRTIO_NET_F_CSUM       = 1 << 0,      // Host handles pkts w/ partial csum
  VIRTIO_NET_F_GUEST_CSUM = 1 << 1,      // Guest handles pkts w/ partial csum
  VIRTIO_NET_F_CTRL_GUEST_OFFLOADS = 1 << 2, // Control channel offloads reconfiguration support.
  VIRTIO_NET_F_MAC        = 1 << 5,      // Host has given MAC address.
  VIRTIO_NET_F_GSO        = 1 << 6,      // Host handles pkts w/ any GSO type
  VIRTIO_NET_F_GUEST_TSO4 = 1 << 7,      // Guest can handle TSOv4 in.
  VIRTIO_NET_F_GUEST_TSO6 = 1 << 8,      // Guest can handle TSOv6 in.
  VIRTIO_NET_F_GUEST_ECN  = 1 << 9,      // Guest can handle TSO[6] w/ ECN in.
  VIRTIO_NET_F_GUEST_UFO  = 1 << 10,     // Guest can handle UFO in.
  VIRTIO_NET_F_HOST_TSO4  = 1 << 11,     // Host can handle TSOv4 in.
  VIRTIO_NET_F_HOST_TSO6  = 1 << 12,     // Host can handle TSOv6 in.
  VIRTIO_NET_F_HOST_ECN   = 1 << 13,     // Host can handle TSO[6] w/ ECN in.
  VIRTIO_NET_F_HOST_UFO   = 1 << 14,     // Host can handle UFO in.
  VIRTIO_NET_F_MRG_RXBUF  = 1 << 15,     // Host can merge receive buffers.
  VIRTIO_NET_F_STATUS     = 1 << 16,     // virtio_net_config.status available
  VIRTIO_NET_F_CTRL_VQ    = 1 << 17,     // Control channel available
  VIRTIO_NET_F_CTRL_RX    = 1 << 18,     // Control channel RX mode support
  VIRTIO_NET_F_CTRL_VLAN  = 1 << 19,     // Control channel VLAN filtering
  VIRTIO_NET_F_CTRL_RX_EXTRA = 1 << 20,  // Extra RX mode control support
  VIRTIO_NET_F_GUEST_ANNOUNCE = 1 << 21, // Guest can announce device on network
  VIRTIO_NET_F_MQ         = 1 << 22,     // Device supports Receive Flow Steering
  VIRTIO_NET_F_CTRL_MAC_ADDR = 1 << 23   // Set MAC address
};

enum {
    VIRTIO_F_NOTIFY_ON_EMPTY = 1 << 24,  /* We notify when the ring is completely used,
                                            even if the guest is suppressing callbacks */
    VIRTIO_F_ANY_LAYOUT = 1 << 27,         // Can the device handle any descriptor layout?
    VIRTIO_RING_F_INDIRECT_DESC = 1 << 28, // We support indirect buffer descriptors
    VIRTIO_RING_F_EVENT_IDX = 1 << 29,     /* The Guest publishes the used index for which
                                              it expects an interrupt at the end of the avail
                                              ring. Host should ignore the avail->flags field.
                                              The Host publishes the avail index for which
                                              it expects a kick at the end of the used ring.
                                              Guest should ignore the used->flags field. */
    VIRTIO_F_BAD_FEATURE = 1 << 30          /* A guest should never accept this.  It implies
                                              negotiation is broken. */
};

struct virtio_net_hdr {
  uint8_t flags;		// See flags enum above
  uint8_t gso_type;		// See GSO type above
  uint16_t hdr_len;
  uint16_t gso_size;
  uint16_t csum_start;
  uint16_t csum_offset;
} __attribute__((packed));

struct virtio_net_hdr_mrg_rxbuf {
  struct virtio_net_hdr hdr;
  uint16_t num_buffers;
} __attribute__((packed));

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

