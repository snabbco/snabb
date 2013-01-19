/* virtio.h - Virtual I/O device support in Linux/KVM style
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 * Copyright 2013 Luke Gorrie.
 */

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
  uint16_t ring[0];
};

struct vring_used_elem {
  uint32_t id;
  uint32_t len;
};

struct vring_used {
  uint16_t flags;
  uint16_t len;
  struct vring_used_elem[0];
};

