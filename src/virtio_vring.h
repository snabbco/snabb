// Size of vring structures used in Linux vhost. Max 512 [citation needed].
enum { VHOST_VRING_SIZE = 512 };

/// ### vring_desc: I/O buffer descriptor

struct vring_desc {
  uint64_t addr;  // packet data buffer address
  uint32_t len;   // packet data buffer size
  uint16_t flags; // (see below)
  uint16_t next;  // optional index next descriptor in chain
};

// Available vring_desc.flags
enum {
  VIRTIO_DESC_F_NEXT = 1,    // Descriptor continues via 'next' field
  VIRTIO_DESC_F_WRITE = 2,   // Write-only descriptor (otherwise read-only)
  VIRTIO_DESC_F_INDIRECT = 4 // Buffer contains a list of descriptors
};

enum { // flags for avail and used rings
  VRING_F_NO_INTERRUPT  = 1,  // Hint: don't bother to kick/interrupt me
  VRING_F_INDIRECT_DESC = 28, // Indirect descriptors are supported
  VRING_F_EVENT_IDX     = 29  // (Some boring complicated interrupt behavior..)
};

// ring of descriptors that are available to be processed
struct vring_avail {
  uint16_t flags;
  uint16_t idx;
  uint16_t ring[VHOST_VRING_SIZE];
};

// ring of descriptors that have already been processed
struct vring_used {
  uint32_t flags;
  uint32_t idx;
  struct { uint32_t id, len; } ring[VHOST_VRING_SIZE];
};

/// ### virtio_net_hdr: packet offload information header

struct virtio_net_hdr {
  uint8_t flags;                // (see below)
  uint8_t gso_type;             // (see below)
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

