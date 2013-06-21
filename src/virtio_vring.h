// Size of vring structures used in Linux vhost. Max 32768.
enum { VHOST_VRING_SIZE = 32*1024 };

// vring_desc I/O buffer descriptor
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
  VRING_F_NO_INTERRUPT  = 1,  // Hint: don't bother to call process
  VRING_F_NO_NOTIFY     = 1,  // Hint: don't bother to kick kernel
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
  uint16_t flags;
  uint16_t idx;
  struct vring_used_elem { uint32_t id; uint32_t len; } ring[VHOST_VRING_SIZE];
};

